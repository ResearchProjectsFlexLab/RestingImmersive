import Foundation
@testable import RestingImmersive

/// A manually advanced clock for deterministic session tests.
@MainActor
final class TestClock {
    var now: TimeInterval = 1_000

    func advance(by seconds: TimeInterval) {
        now += seconds
    }

    func makeSession() -> MeditationSession {
        MeditationSession(now: { [unowned self] in self.now }, tickInterval: nil)
    }
}
