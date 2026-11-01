import Foundation
import Testing
@testable import RestingImmersive

@MainActor
struct SessionLogTests {
    let clock = TestClock()

    private func started(duration: TimeInterval = 60, guided: Bool = true) -> MeditationSession {
        let session = clock.makeSession()
        session.start(.init(duration: duration, guidedBreathing: guided))
        return session
    }

    private func kinds(_ session: MeditationSession) -> [SessionEventKind] {
        session.log.entries.map(\.kind)
    }

    @Test func startWritesHeaderStartAndFirstBreath() {
        let session = started()
        #expect(kinds(session) == [.session, .started, .breathingPhase])
        #expect(session.log.entries.last?.breathingPhase == .inhale)
        #expect(session.log.entries.allSatisfy { $0.timestamp == Date(timeIntervalSince1970: 1_000) })
    }

    @Test func unguidedSessionLogsNoBreathingPhases() {
        let session = started(guided: false)
        clock.advance(by: 5)
        session.tick()
        #expect(kinds(session) == [.session, .started])
    }

    @Test func everyPhaseChangeIsTimestamped() {
        let session = started()
        clock.advance(by: 4)
        session.tick()
        clock.advance(by: 6)
        session.tick()
        let phases = session.log.entries.filter { $0.kind == .breathingPhase }
        #expect(phases.map(\.breathingPhase) == [.inhale, .exhale, .inhale])
        #expect(phases.map(\.timestamp.timeIntervalSince1970) == [1_000, 1_004, 1_010])
        #expect(phases.map(\.elapsed) == [0, 4, 10])
    }

    @Test func heartbeatEveryTenSessionSeconds() {
        let session = started(duration: 60, guided: false)
        for _ in 0..<25 {
            clock.advance(by: 1)
            session.tick()
        }
        let beats = session.log.entries.filter { $0.kind == .heartbeat }
        #expect(beats.map(\.elapsed) == [10, 20])
    }

    @Test func pauseResumeInterruptionAndEndAreLogged() {
        let session = started(guided: false)
        clock.advance(by: 2)
        session.pause()
        clock.advance(by: 30)
        session.resume()
        session.handleInterruption()
        session.resume()
        session.end()
        #expect(kinds(session) == [.session, .started, .paused, .resumed, .interrupted, .resumed, .endedEarly])
        let paused = session.log.entries[2]
        #expect(paused.elapsed == 2)
        #expect(paused.remaining == 58)
        #expect(paused.timestamp == Date(timeIntervalSince1970: 1_002))
        #expect(session.log.entries.last?.timestamp == Date(timeIntervalSince1970: 1_032))
    }

    @Test func completionIsLogged() {
        let session = started(duration: 5, guided: false)
        clock.advance(by: 5)
        session.tick()
        #expect(session.log.entries.last?.kind == .completed)
        #expect(session.log.entries.last?.remaining == 0)
    }

    @Test func logSurvivesResetButNewSessionStartsFresh() {
        let session = started(guided: false)
        session.reset()
        #expect(kinds(session) == [.session, .started, .discarded])

        session.reset()
        #expect(kinds(session).count == 3, "Resetting an idle session logs nothing")

        session.start(.init(duration: 60, guidedBreathing: false))
        #expect(kinds(session) == [.session, .started])
    }

    @Test func textAndCSVExportsIncludeTimestamps() {
        let session = started(guided: false)
        clock.advance(by: 1.5)
        session.end()

        let stamp = LogClock.string(from: Date(timeIntervalSince1970: 1_001.5))
        #expect(session.log.text.contains("\(stamp)  ended early  elapsed 0:01.5  remaining 0:58.5"))
        #expect(session.log.text.contains("Entries: 3"))

        let rows = session.log.csvText.split(separator: "\n")
        #expect(rows.first == "timestamp,unix_ms,event,elapsed_seconds,remaining_seconds,breathing_phase,message")
        #expect(rows.count == 4)
        #expect(rows.last?.hasPrefix("\(stamp),1001500,endedEarly,1.500,58.500,,") == true)
    }

    // MARK: Research-grade timing

    @Test func stalledTickStillLogsEveryMilestoneAtItsExactMoment() {
        let session = started(duration: 60)
        clock.advance(by: 25)
        session.tick()

        let milestones = session.log.entries.filter { $0.kind == .breathingPhase || $0.kind == .heartbeat }
        #expect(milestones.map(\.kind) == [
            .breathingPhase, .breathingPhase, .breathingPhase, .heartbeat,
            .breathingPhase, .breathingPhase, .heartbeat, .breathingPhase,
        ])
        #expect(milestones.map(\.elapsed) == [0, 4, 10, 10, 14, 20, 20, 24])
        #expect(milestones.map { $0.timestamp.timeIntervalSince1970 } == [1_000, 1_004, 1_010, 1_010, 1_014, 1_020, 1_020, 1_024])
        #expect(milestones.compactMap(\.breathingPhase) == [.inhale, .exhale, .inhale, .inhale, .exhale, .inhale, .inhale, .exhale])
    }

    @Test func lateTickStampsCompletionWhenTimeActuallyRanOut() {
        let session = started(duration: 5, guided: false)
        clock.advance(by: 7)
        session.tick()
        let completed = session.log.entries.last
        #expect(completed?.kind == .completed)
        #expect(completed?.elapsed == 5)
        #expect(completed?.timestamp == Date(timeIntervalSince1970: 1_005))
    }

    @Test func milestonesAfterPauseUseOnlyRunningTime() {
        let session = started(duration: 60)
        clock.advance(by: 3)
        session.pause()
        clock.advance(by: 100)
        session.resume()
        clock.advance(by: 2)
        session.tick()
        let exhale = session.log.entries.first { $0.breathingPhase == .exhale && $0.kind == .breathingPhase }
        #expect(exhale?.elapsed == 4)
        #expect(exhale?.timestamp == Date(timeIntervalSince1970: 1_104))
    }

    @Test func timestampsAreISO8601WithOffsetAndMilliseconds() {
        let text = LogClock.string(from: Date(timeIntervalSince1970: 1_001.5))
        #expect(text.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.500(Z|[+-]\d{2}:\d{2})/) != nil)
        #expect(LogClock.unixMilliseconds(from: Date(timeIntervalSince1970: 1_001.5)) == 1_001_500)
    }
}
