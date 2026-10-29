import Foundation
import Testing
@testable import RestingImmersive

@MainActor
struct MeditationSessionTests {
    let clock = TestClock()

    private func started(duration: TimeInterval = 60, guided: Bool = true) -> MeditationSession {
        let session = clock.makeSession()
        session.start(.init(duration: duration, guidedBreathing: guided))
        return session
    }

    // MARK: Timing

    @Test func startsRunningWithFullDuration() {
        let session = started(duration: 300)
        #expect(session.status == .running)
        #expect(session.remainingSeconds == 300)
        #expect(session.currentElapsed() == 0)
        #expect(session.breathingPhase == .inhale)
    }

    @Test func countdownFollowsTheClock() {
        let session = started(duration: 300)
        clock.advance(by: 0.4)
        session.tick()
        #expect(session.remainingSeconds == 300, "Rounds up until a full second has passed")

        clock.advance(by: 0.6)
        session.tick()
        #expect(session.remainingSeconds == 299)

        clock.advance(by: 120)
        session.tick()
        #expect(session.remainingSeconds == 179)
        #expect(abs(session.remaining - 179) < 1e-9)
    }

    @Test func irregularTicksDoNotCauseDrift() {
        let session = started(duration: 600)
        for interval in [0.13, 0.27, 0.05, 1.9, 0.33, 0.07] {
            clock.advance(by: interval)
            session.tick()
        }
        #expect(abs(session.currentElapsed() - 2.75) < 1e-9)
    }

    @Test func completesExactlyAtDuration() {
        let session = started(duration: 10)
        clock.advance(by: 9.99)
        session.tick()
        #expect(session.status == .running)

        clock.advance(by: 0.01)
        session.tick()
        #expect(session.status == .completed)
        #expect(session.remainingSeconds == 0)
        #expect(session.currentElapsed() == 10)
        #expect(session.breathingPhase == nil)
        #expect(!session.isTicking)
    }

    @Test func overshootingTheDurationClampsElapsedTime() {
        let session = started(duration: 10)
        clock.advance(by: 500)
        session.tick()
        #expect(session.status == .completed)
        #expect(session.currentElapsed() == 10)
    }

    // MARK: Pause / resume

    @Test func pausePreservesRemainingTime() {
        let session = started(duration: 60)
        clock.advance(by: 12.5)
        session.pause()
        #expect(session.status == .paused)
        #expect(session.remainingSeconds == 48)

        clock.advance(by: 1_000)
        session.tick()
        #expect(abs(session.currentElapsed() - 12.5) < 1e-9)
        #expect(session.remainingSeconds == 48)
    }

    @Test func resumeContinuesFromSameTimeAndPhase() {
        let session = started(duration: 60)
        clock.advance(by: 5) // 1 second into the exhale
        session.pause()
        let pausedState = session.breathingState()
        #expect(pausedState?.phase == .exhale)

        clock.advance(by: 30)
        session.resume()
        #expect(session.status == .running)
        #expect(session.breathingState() == pausedState)

        clock.advance(by: 5) // elapsed 10 → new inhale
        session.tick()
        #expect(abs(session.currentElapsed() - 10) < 1e-9)
        #expect(session.breathingPhase == .inhale)
    }

    @Test func repeatedPauseAndResumeAccumulateCorrectly() {
        let session = started(duration: 120)
        for _ in 0..<5 {
            clock.advance(by: 3)
            session.pause()
            clock.advance(by: 50)
            session.resume()
        }
        #expect(abs(session.currentElapsed() - 15) < 1e-9)
    }

    @Test func pauseAndResumeAreIgnoredInWrongStates() {
        let session = clock.makeSession()
        session.pause()
        session.resume()
        #expect(session.status == .idle)

        session.start(.init(duration: 30, guidedBreathing: true))
        session.resume()
        #expect(session.status == .running)
        session.pause()
        session.pause()
        #expect(session.status == .paused)
    }

    @Test func pausingAfterTimeRanOutCompletesInsteadOfPausing() {
        let session = started(duration: 10)
        clock.advance(by: 11)
        session.pause()
        #expect(session.status == .completed)
    }

    @Test func togglePauseSwitchesBetweenStates() {
        let session = started()
        session.togglePause()
        #expect(session.status == .paused)
        session.togglePause()
        #expect(session.status == .running)
    }

    // MARK: Breathing

    @Test func breathingPhasesAlternateOverTime() {
        let session = started(duration: 60)
        var phases: [BreathingPhase?] = []
        for _ in 0..<20 {
            session.tick()
            phases.append(session.breathingPhase)
            clock.advance(by: 1)
        }
        let expected: [BreathingPhase] = (0..<20).map { $0 % 10 < 4 ? .inhale : .exhale }
        #expect(phases == expected)
    }

    @Test func unguidedSessionsHaveNoBreathingState() {
        let session = started(guided: false)
        clock.advance(by: 2)
        session.tick()
        #expect(session.breathingPhase == nil)
        #expect(session.breathingState() == nil)
        #expect(session.breathingExpansion() == nil)
        #expect(session.status == .running)
    }

    @Test func expansionFreezesWhilePaused() {
        let session = started()
        clock.advance(by: 2)
        session.pause()
        let frozen = session.breathingExpansion()
        clock.advance(by: 3)
        #expect(session.breathingExpansion() == frozen)
    }

    // MARK: Ending

    @Test func endingEarlyIsNotCompletion() {
        let session = started(duration: 60)
        clock.advance(by: 20)
        session.end()
        #expect(session.status == .endedEarly)
        #expect(abs(session.currentElapsed() - 20) < 1e-9)
        #expect(session.breathingPhase == nil)
        #expect(!session.isTicking)
    }

    @Test func endingWhilePausedIsEndedEarly() {
        let session = started(duration: 60)
        clock.advance(by: 5)
        session.pause()
        session.end()
        #expect(session.status == .endedEarly)
    }

    @Test func endingAfterTimeRanOutReportsCompletion() {
        let session = started(duration: 10)
        clock.advance(by: 10)
        session.end()
        #expect(session.status == .completed)
    }

    @Test func endIsIgnoredOnceFinished() {
        let session = started(duration: 10)
        clock.advance(by: 10)
        session.tick()
        session.end()
        #expect(session.status == .completed)
    }

    @Test func resetReturnsToIdle() {
        let session = started()
        clock.advance(by: 4)
        session.reset()
        #expect(session.status == .idle)
        #expect(session.currentElapsed() == 0)
        #expect(!session.isTicking)
    }

    @Test func restartingClearsPreviousSession() {
        let session = started(duration: 60)
        clock.advance(by: 30)
        session.pause()
        session.start(.init(duration: 120, guidedBreathing: false))
        #expect(session.status == .running)
        #expect(session.currentElapsed() == 0)
        #expect(session.remainingSeconds == 120)
        #expect(!session.wasInterrupted)
    }

    // MARK: Interruptions

    @Test func interruptionPausesAndFlagsSession() {
        let session = started(duration: 60)
        clock.advance(by: 8)
        session.handleInterruption()
        #expect(session.status == .paused)
        #expect(session.wasInterrupted)

        clock.advance(by: 600)
        session.resume()
        #expect(!session.wasInterrupted)
        #expect(abs(session.currentElapsed() - 8) < 1e-9)
    }

    @Test func interruptionDoesNotAffectInactiveSessions() {
        let session = started(duration: 60)
        session.pause()
        session.handleInterruption()
        #expect(!session.wasInterrupted, "A user-initiated pause is not an interruption")

        let idle = clock.makeSession()
        idle.handleInterruption()
        #expect(idle.status == .idle)
    }
}

/// Exercises the real timer task, using the real clock.
@MainActor
struct MeditationSessionTickerTests {
    @Test func tickerRunsOnlyWhileRunning() async throws {
        let session = MeditationSession(tickInterval: .milliseconds(20))
        #expect(!session.isTicking)
        session.start(.init(duration: 60, guidedBreathing: true))
        #expect(session.isTicking)
        session.pause()
        #expect(!session.isTicking)
        session.resume()
        #expect(session.isTicking)
        session.end()
        #expect(!session.isTicking)
    }

    @Test func restartingDoesNotCreateOverlappingTickers() async throws {
        let session = MeditationSession(tickInterval: .milliseconds(20))
        for _ in 0..<5 {
            session.start(.init(duration: 60, guidedBreathing: true))
        }
        #expect(session.isTicking)
        session.reset()
        #expect(!session.isTicking)
    }

    @Test func tickerCompletesShortSessionOnItsOwn() async throws {
        let session = MeditationSession(tickInterval: .milliseconds(20))
        session.start(.init(duration: 1, guidedBreathing: true))
        let deadline = ContinuousClock.now + .seconds(5)
        while session.status == .running, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(session.status == .completed)
        #expect(session.remainingSeconds == 0)
        #expect(!session.isTicking)
    }
}
