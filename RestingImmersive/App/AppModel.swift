import Foundation
import Observation

/// App-wide state: the user's session preferences, the immersive space lifecycle,
/// and the outcome of the most recent session.
@MainActor
@Observable
final class AppModel {
    enum ImmersiveSpaceState: Equatable {
        case closed
        case opening
        case open
        case closing
    }

    enum SessionOutcome: Equatable {
        case completed(duration: TimeInterval)
        case endedEarly(elapsed: TimeInterval)
    }

    static let immersiveSpaceID = "Sanctuary"
    static let mainWindowID = "Main"
    static let durationOptions: [Int] = [1, 5, 10, 20]

    let session: MeditationSession

    var selectedMinutes = 10
    var guidedBreathing = true
    var ambientSound = true

    private(set) var immersiveSpaceState: ImmersiveSpaceState = .closed
    private(set) var lastOutcome: SessionOutcome?
    var errorMessage: String?
    var isMainWindowOpen = false
    @ObservationIgnored private var isSanctuaryReady = false

    init(session: MeditationSession = MeditationSession()) {
        self.session = session
    }

    var canBeginSession: Bool { immersiveSpaceState == .closed }

    var configuration: MeditationSession.Configuration {
        .init(duration: TimeInterval(selectedMinutes * 60), guidedBreathing: guidedBreathing)
    }

    // MARK: - Immersive space lifecycle

    /// Call before requesting the immersive space. Returns `false` if a request is already in flight.
    func beginOpening() -> Bool {
        guard immersiveSpaceState == .closed else { return false }
        errorMessage = nil
        lastOutcome = nil
        isSanctuaryReady = false
        immersiveSpaceState = .opening
        return true
    }

    /// The system presented the space. The session starts once the scene is also ready.
    func didOpenImmersiveSpace() {
        guard immersiveSpaceState == .opening else { return }
        immersiveSpaceState = .open
        startSessionIfReady()
    }

    /// The sanctuary finished building and is about to fade in. This can arrive before
    /// or after `didOpenImmersiveSpace()`; the countdown waits for both so no time
    /// passes while the user is looking at an empty space.
    func sanctuaryDidBecomeReady() {
        guard immersiveSpaceState == .opening || immersiveSpaceState == .open else { return }
        isSanctuaryReady = true
        startSessionIfReady()
    }

    private func startSessionIfReady() {
        guard immersiveSpaceState == .open, isSanctuaryReady, session.status == .idle else { return }
        session.start(configuration)
    }

    /// The system declined or failed to present the space.
    func didFailToOpenImmersiveSpace(userCancelled: Bool) {
        guard immersiveSpaceState == .opening else { return }
        immersiveSpaceState = .closed
        isSanctuaryReady = false
        session.reset()
        errorMessage = userCancelled
            ? nil
            : String(localized: "The sanctuary couldn’t open. Please try again.")
    }

    /// The user asked to leave. Ends an unfinished session early.
    @discardableResult
    func beginClosing() -> Bool {
        guard immersiveSpaceState == .open else { return false }
        recordOutcomeEndingIfNeeded()
        immersiveSpaceState = .closing
        return true
    }

    /// The immersive content disappeared, whether requested or not (Digital Crown,
    /// system dismissal, or a failed dismissal request). Always leaves a consistent state.
    func immersiveSpaceDidClose() {
        if immersiveSpaceState != .closed {
            recordOutcomeEndingIfNeeded()
        }
        immersiveSpaceState = .closed
        isSanctuaryReady = false
        session.reset()
    }

    private func recordOutcomeEndingIfNeeded() {
        switch session.status {
        case .running, .paused:
            session.end()
            lastOutcome = .endedEarly(elapsed: session.currentElapsed())
        case .completed:
            lastOutcome = .completed(duration: session.configuration.duration)
        case .endedEarly:
            if lastOutcome == nil {
                lastOutcome = .endedEarly(elapsed: session.currentElapsed())
            }
        case .idle:
            break
        }
    }
}
