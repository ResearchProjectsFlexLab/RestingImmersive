import Foundation
import Observation
import os

/// Everything worth a line in the session log.
enum SessionEventKind: String, Equatable, Sendable {
    case session
    case started
    case breathingPhase
    case heartbeat
    case paused
    case interrupted
    case resumed
    case completed
    case endedEarly
    case discarded
}

struct SessionLogEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Wall-clock time the event happened.
    let timestamp: Date
    /// `timestamp` as whole milliseconds since 1970 UTC, for joining with sensor data.
    var unixMilliseconds: Int64 { LogClock.unixMilliseconds(from: timestamp) }
    let kind: SessionEventKind
    /// Session time elapsed when the event happened (pauses excluded).
    let elapsed: TimeInterval
    let remaining: TimeInterval
    let breathingPhase: BreathingPhase?
    let line: String
}

enum LogClock {
    /// ISO 8601 local time with milliseconds and UTC offset, e.g. `2026-11-01T15:35:48.648-05:00`,
    /// so every line is unambiguous when lined up with sensor recordings.
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func unixMilliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

/// Appends to `Documents/session-log.txt` (readable) and `Documents/session-log.csv`
/// (for analysis). Both keep every session ever run and are visible in the Files app
/// (see `UIFileSharingEnabled` in Info.plist).
enum SessionLogFile {
    static let textName = "session-log.txt"
    static let csvName = "session-log.csv"

    static func url(named name: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name)
    }

    /// Appends `line`. A new file starts with `header` when one is given.
    static func append(_ line: String, to name: String, header: String? = nil) {
        guard let url = url(named: name) else { return }
        let payload = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            let start = header.map { Data(($0 + "\n").utf8) } ?? Data()
            try? (start + payload).write(to: url, options: .atomic)
        }
    }
}

/// A timestamped record of one meditation session: start, every breathing phase,
/// a periodic heartbeat, pauses, interruptions, and how the session ended.
///
/// Each entry goes to three places: the in-memory `entries` (for export),
/// the unified system log (Console.app, subsystem `RestingImmersive`), and,
/// when `persists` is true, the text file in Documents.
@MainActor
@Observable
final class SessionLog {
    static let maxEntries = 2000

    private(set) var entries: [SessionLogEntry] = []

    @ObservationIgnored let persists: Bool
    @ObservationIgnored private let wallClock: @MainActor () -> Date
    @ObservationIgnored private let logger = Logger(subsystem: "RestingImmersive", category: "Session")

    init(persists: Bool = true, wallClock: @escaping @MainActor () -> Date = { Date() }) {
        self.persists = persists
        self.wallClock = wallClock
    }

    var isEmpty: Bool { entries.isEmpty }

    /// The wall clock the log stamps entries with.
    func currentTime() -> Date { wallClock() }

    /// Plain-text export of every entry, in the order it was written.
    var text: String {
        var lines = [
            "Resting session log",
            "Generated: \(LogClock.string(from: entries.last?.timestamp ?? wallClock()))",
            "Time zone: \(TimeZone.current.identifier)",
            "Entries: \(entries.count)",
            "Each line: local time with UTC offset, event, session time elapsed and remaining (pauses excluded).",
            "",
        ]
        lines.append(contentsOf: entries.map(\.line))
        return lines.joined(separator: "\n")
    }

    /// Spreadsheet export of every entry, including timestamps.
    var csvText: String {
        var rows = [Self.csvHeader]
        rows.reserveCapacity(entries.count + 1)
        rows.append(contentsOf: entries.map(Self.csvRow))
        return rows.joined(separator: "\n")
    }

    static let csvHeader = "timestamp,unix_ms,event,elapsed_seconds,remaining_seconds,breathing_phase,message"

    static func csvRow(_ entry: SessionLogEntry) -> String {
        let fields = [
            LogClock.string(from: entry.timestamp),
            String(entry.unixMilliseconds),
            entry.kind.rawValue,
            String(format: "%.3f", entry.elapsed),
            String(format: "%.3f", entry.remaining),
            entry.breathingPhase?.rawValue ?? "",
            entry.line,
        ]
        return fields.map(csvField).joined(separator: ",")
    }

    /// Clears the in-memory entries. The text file keeps earlier sessions.
    func clear() {
        entries.removeAll()
    }

    /// - Parameter timestamp: When the event happened. Defaults to now; pass an earlier
    ///   time for events noticed after the fact.
    func record(
        _ kind: SessionEventKind,
        timestamp: Date? = nil,
        elapsed: TimeInterval,
        remaining: TimeInterval,
        breathingPhase: BreathingPhase? = nil,
        detail: String? = nil
    ) {
        let now = timestamp ?? wallClock()
        let line = Self.makeLine(
            kind: kind, at: now, elapsed: elapsed, remaining: remaining,
            breathingPhase: breathingPhase, detail: detail
        )
        let entry = SessionLogEntry(
            id: UUID(),
            timestamp: now,
            kind: kind,
            elapsed: elapsed,
            remaining: remaining,
            breathingPhase: breathingPhase,
            line: line
        )
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        logger.info("\(line, privacy: .public)")
        if persists {
            SessionLogFile.append(line, to: SessionLogFile.textName)
            SessionLogFile.append(Self.csvRow(entry), to: SessionLogFile.csvName, header: Self.csvHeader)
        }
    }

    private static func makeLine(
        kind: SessionEventKind,
        at now: Date,
        elapsed: TimeInterval,
        remaining: TimeInterval,
        breathingPhase: BreathingPhase?,
        detail: String?
    ) -> String {
        let time = LogClock.string(from: now)
        let clock = "elapsed \(clockText(elapsed))  remaining \(clockText(remaining))"
        let event: String = switch kind {
        case .session: "---------- session \(time) ----------"
        case .started: "started  \(detail ?? "")"
        case .breathingPhase: (breathingPhase?.instruction ?? "breathing").lowercased()
        case .heartbeat: "resting"
        case .paused: "paused"
        case .interrupted: "paused (app lost focus)"
        case .resumed: "resumed"
        case .completed: "completed"
        case .endedEarly: "ended early"
        case .discarded: "discarded"
        }
        if kind == .session { return event }
        return "\(time)  \(event)  \(clock)"
    }

    /// "1:23.4" style session time.
    private static func clockText(_ seconds: TimeInterval) -> String {
        let seconds = max(0, seconds)
        let minutes = Int(seconds) / 60
        return String(format: "%d:%04.1f", minutes, seconds - TimeInterval(minutes * 60))
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
