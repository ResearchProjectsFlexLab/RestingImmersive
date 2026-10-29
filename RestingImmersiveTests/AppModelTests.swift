import Foundation
import Testing
@testable import RestingImmersive

@MainActor
struct AppModelTests {
    let clock = TestClock()

    private func makeModel(minutes: Int = 1, guided: Bool = true) -> AppModel {
        let model = AppModel(session: clock.makeSession())
        model.selectedMinutes = minutes
        model.guidedBreathing = guided
        return model
    }

    private func enter(_ model: AppModel) {
        _ = model.beginOpening()
        model.didOpenImmersiveSpace()
        model.sanctuaryDidBecomeReady()
    }

    @Test func sceneReadyBeforeOpenResultStillStartsOnce() {
        let model = makeModel()
        _ = model.beginOpening()
        model.sanctuaryDidBecomeReady()
        #expect(model.session.status == .idle)
        model.didOpenImmersiveSpace()
        #expect(model.session.status == .running)

        clock.advance(by: 7)
        model.sanctuaryDidBecomeReady()
        #expect(abs(model.session.currentElapsed() - 7) < 1e-9, "A repeated ready signal must not restart the session")
    }

    @Test func noTimePassesWhileTheSceneIsLoading() {
        let model = makeModel(minutes: 1)
        _ = model.beginOpening()
        model.didOpenImmersiveSpace()
        clock.advance(by: 40)
        model.sanctuaryDidBecomeReady()
        #expect(model.session.remainingSeconds == 60)
    }

    @Test func leavingBeforeTheSceneIsReadyRecordsNoOutcome() {
        let model = makeModel()
        _ = model.beginOpening()
        model.didOpenImmersiveSpace()
        #expect(model.beginClosing())
        model.immersiveSpaceDidClose()
        model.sanctuaryDidBecomeReady()
        #expect(model.lastOutcome == nil)
        #expect(model.session.status == .idle)
        #expect(model.canBeginSession)
    }

    @Test func openingStartsSessionWithSelectedConfiguration() {
        let model = makeModel(minutes: 5, guided: false)
        #expect(model.beginOpening())
        #expect(model.immersiveSpaceState == .opening)
        #expect(!model.canBeginSession)

        model.didOpenImmersiveSpace()
        #expect(model.immersiveSpaceState == .open)
        #expect(model.session.status == .idle, "The countdown waits for the scene")

        model.sanctuaryDidBecomeReady()
        #expect(model.session.status == .running)
        #expect(model.session.configuration == .init(duration: 300, guidedBreathing: false))
    }

    @Test func duplicateOpenRequestsAreRejected() {
        let model = makeModel()
        #expect(model.beginOpening())
        #expect(!model.beginOpening())
        model.didOpenImmersiveSpace()
        #expect(!model.beginOpening())
    }

    @Test func openingFailureReturnsToClosedWithMessage() {
        let model = makeModel()
        _ = model.beginOpening()
        model.didFailToOpenImmersiveSpace(userCancelled: false)
        #expect(model.immersiveSpaceState == .closed)
        #expect(model.errorMessage != nil)
        #expect(model.session.status == .idle)
        #expect(model.canBeginSession)
    }

    @Test func userCancellationIsNotAnError() {
        let model = makeModel()
        _ = model.beginOpening()
        model.didFailToOpenImmersiveSpace(userCancelled: true)
        #expect(model.immersiveSpaceState == .closed)
        #expect(model.errorMessage == nil)
    }

    @Test func endingEarlyRecordsEarlyOutcome() {
        let model = makeModel(minutes: 1)
        enter(model)
        clock.advance(by: 25)

        #expect(model.beginClosing())
        #expect(model.immersiveSpaceState == .closing)
        model.immersiveSpaceDidClose()

        #expect(model.immersiveSpaceState == .closed)
        #expect(model.lastOutcome == .endedEarly(elapsed: 25))
        #expect(model.session.status == .idle)
        #expect(model.canBeginSession)
    }

    @Test func completedSessionRecordsCompletion() {
        let model = makeModel(minutes: 1)
        enter(model)
        clock.advance(by: 60)
        model.session.tick()
        #expect(model.session.status == .completed)

        model.beginClosing()
        model.immersiveSpaceDidClose()
        #expect(model.lastOutcome == .completed(duration: 60))
    }

    @Test func unexpectedDismissalEndsSessionEarly() {
        let model = makeModel(minutes: 1)
        enter(model)
        clock.advance(by: 10)
        model.session.handleInterruption()

        // e.g. the user pressed the Digital Crown; no beginClosing() call.
        model.immersiveSpaceDidClose()
        #expect(model.immersiveSpaceState == .closed)
        #expect(model.lastOutcome == .endedEarly(elapsed: 10))
        #expect(model.session.status == .idle)
    }

    @Test func spaceClosingBeforeOpenResultArrivesStaysConsistent() {
        let model = makeModel()
        _ = model.beginOpening()
        model.immersiveSpaceDidClose()
        model.didOpenImmersiveSpace() // late result must not resurrect a session
        #expect(model.immersiveSpaceState == .closed)
        #expect(model.session.status == .idle)
    }

    @Test func repeatedCloseCallsAreHarmless() {
        let model = makeModel()
        enter(model)
        clock.advance(by: 5)
        model.beginClosing()
        model.immersiveSpaceDidClose()
        model.immersiveSpaceDidClose()
        #expect(!model.beginClosing())
        #expect(model.lastOutcome == .endedEarly(elapsed: 5))
        #expect(model.immersiveSpaceState == .closed)
    }

    @Test func newSessionClearsPreviousOutcome() {
        let model = makeModel()
        enter(model)
        model.beginClosing()
        model.immersiveSpaceDidClose()
        #expect(model.lastOutcome != nil)

        _ = model.beginOpening()
        #expect(model.lastOutcome == nil)
    }

    @Test func countdownFormatting() {
        #expect(TimeFormatting.countdown(0) == "0:00")
        #expect(TimeFormatting.countdown(65) == "1:05")
        #expect(TimeFormatting.countdown(1200) == "20:00")
        #expect(TimeFormatting.countdown(-3) == "0:00")
    }
}
