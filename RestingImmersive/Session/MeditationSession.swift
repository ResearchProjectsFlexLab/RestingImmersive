import Foundation
import Observation

/// The single source of truth for a meditation session's timing and breathing state.
///
/// Elapsed time is always derived from a monotonic clock (`now`) plus time
/// accumulated before the most recent pause, so ticks only refresh what is
/// displayed and never accumulate drift.
@MainActor
@Observable
final class MeditationSession {
    enum Status: Equatable, Sendable {
        case idle
        case running
        case paused
        case completed
        case endedEarly
    }

    struct Configuration: Equatable, Sendable {
        var duration: TimeInterval
        var guidedBreathing: Bool

        static let `default` = Configuration(duration: 10 * 60, guidedBreathing: true)
    }

    private(set) var status: Status = .idle
    private(set) var configuration: Configuration = .default

    /// Whole seconds left, rounded up so the display reads "0:00" only at the very end.
    private(set) var remainingSeconds = Int(Configuration.default.duration)
    /// Current guided-breathing phase, or `nil` when guidance is off or the session is inactive.
    private(set) var breathingPhase: BreathingPhase?
    /// True when the session was paused automatically because the app lost focus.
    private(set) var wasInterrupted = false

    @ObservationIgnored private var accumulatedElapsed: TimeInterval = 0
    @ObservationIgnored private var runningSince: TimeInterval?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    @ObservationIgnored private let now: @MainActor () -> TimeInterval
    @ObservationIgnored private let tickInterval: Duration?

    /// - Parameters:
    ///   - now: Monotonic clock in seconds. Injected so tests can control time.
    ///   - tickInterval: How often to refresh the display. `nil` disables the
    ///     internal ticker entirely so tests can call `tick()` themselves.
    init(
        now: @escaping @MainActor () -> TimeInterval = MeditationSession.monotonicNow,
        tickInterval: Duration? = .milliseconds(100)
    ) {
        self.now = now
        self.tickInterval = tickInterval
    }

    // MARK: - Derived state

    var isActive: Bool { status == .running || status == .paused }
    var isFinished: Bool { status == .completed || status == .endedEarly }

    /// Precise elapsed time for the current moment. Cheap enough to call every frame.
    func currentElapsed() -> TimeInterval {
        var elapsed = accumulatedElapsed
        if let runningSince {
            elapsed += max(0, now() - runningSince)
        }
        return min(elapsed, configuration.duration)
    }

    var remaining: TimeInterval {
        max(0, configuration.duration - currentElapsed())
    }

    func breathingState() -> BreathingState? {
        guard configuration.guidedBreathing, isActive else { return nil }
        return BreathingCycle.state(atElapsed: currentElapsed())
    }

    /// Breath expansion in `0...1` for the orb, or `nil` when the orb should rest.
    func breathingExpansion() -> Double? {
        guard configuration.guidedBreathing, isActive else { return nil }
        return BreathingCycle.expansion(atElapsed: currentElapsed())
    }

    // MARK: - Commands

    func start(_ configuration: Configuration) {
        stopTicking()
        self.configuration = Configuration(
            duration: max(1, configuration.duration),
            guidedBreathing: configuration.guidedBreathing
        )
        accumulatedElapsed = 0
        runningSince = now()
        wasInterrupted = false
        status = .running
        refreshDisplayedState()
        startTicking()
    }

    func pause() {
        guard status == .running else { return }
        tick()
        guard status == .running else { return }
        accumulatedElapsed = currentElapsed()
        runningSince = nil
        status = .paused
        stopTicking()
        refreshDisplayedState()
    }

    func resume() {
        guard status == .paused else { return }
        runningSince = now()
        wasInterrupted = false
        status = .running
        refreshDisplayedState()
        startTicking()
    }

    func togglePause() {
        switch status {
        case .running: pause()
        case .paused: resume()
        default: break
        }
    }

    /// Ends the session at the user's request (or because the space went away).
    /// A session that already reached its full duration stays `.completed`.
    func end() {
        guard isActive else { return }
        tick()
        guard isActive else { return }
        accumulatedElapsed = currentElapsed()
        runningSince = nil
        status = .endedEarly
        stopTicking()
        refreshDisplayedState()
    }

    /// The app became inactive or the immersive space lost focus.
    func handleInterruption() {
        guard status == .running else { return }
        pause()
        if status == .paused {
            wasInterrupted = true
        }
    }

    /// Returns to a clean idle state, discarding any session in progress.
    func reset() {
        stopTicking()
        accumulatedElapsed = 0
        runningSince = nil
        wasInterrupted = false
        status = .idle
        refreshDisplayedState()
    }

    /// Re-reads the clock, publishes display values, and completes the session when time is up.
    func tick() {
        guard status == .running else { return }
        if currentElapsed() >= configuration.duration {
            accumulatedElapsed = configuration.duration
            runningSince = nil
            status = .completed
            stopTicking()
        }
        refreshDisplayedState()
    }

    // MARK: - Internals

    var elapsedBeforeCurrentRun: TimeInterval { accumulatedElapsed }
    var isTicking: Bool { tickTask != nil }

    private func refreshDisplayedState() {
        let seconds: Int = switch status {
        case .idle: Int(configuration.duration.rounded(.up))
        case .completed: 0
        default: Int(remaining.rounded(.up))
        }
        if seconds != remainingSeconds { remainingSeconds = seconds }

        let phase = breathingState()?.phase
        if phase != breathingPhase { breathingPhase = phase }
    }

    private func startTicking() {
        stopTicking()
        guard let tickInterval else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    nonisolated static func monotonicNow() -> TimeInterval {
        let duration = ContinuousClock.now - referenceInstant
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
    }

    private nonisolated static let referenceInstant = ContinuousClock.now
}
