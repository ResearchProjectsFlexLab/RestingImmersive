import Foundation
import Testing
@testable import RestingImmersive

struct BreathingCycleTests {
    @Test func patternIsFourInSixOut() {
        #expect(BreathingCycle.inhaleDuration == 4)
        #expect(BreathingCycle.exhaleDuration == 6)
        #expect(BreathingCycle.cycleDuration == 10)
    }

    @Test(arguments: [
        (0.0, BreathingPhase.inhale),
        (3.99, .inhale),
        (4.0, .exhale),
        (9.99, .exhale),
        (10.0, .inhale),
        (14.0, .exhale),
        (123.5, .inhale),
        (127.0, .exhale),
    ])
    func phaseAtElapsed(elapsed: Double, expected: BreathingPhase) {
        #expect(BreathingCycle.state(atElapsed: elapsed).phase == expected)
    }

    @Test func progressAndRemainingTimeWithinPhases() {
        let inhale = BreathingCycle.state(atElapsed: 1)
        #expect(abs(inhale.progress - 0.25) < 1e-9)
        #expect(abs(inhale.secondsRemainingInPhase - 3) < 1e-9)

        let exhale = BreathingCycle.state(atElapsed: 7)
        #expect(abs(exhale.progress - 0.5) < 1e-9)
        #expect(abs(exhale.secondsRemainingInPhase - 3) < 1e-9)
    }

    @Test func expansionRisesDuringInhaleAndFallsDuringExhale() {
        #expect(BreathingCycle.expansion(atElapsed: 0) < 1e-9)
        #expect(abs(BreathingCycle.expansion(atElapsed: 4) - 1) < 1e-9)
        #expect(BreathingCycle.expansion(atElapsed: 10) < 1e-9)

        var previous = BreathingCycle.expansion(atElapsed: 0)
        for step in 1...40 {
            let value = BreathingCycle.expansion(atElapsed: Double(step) * 0.1)
            #expect(value >= previous)
            previous = value
        }
        for step in 41...100 {
            let value = BreathingCycle.expansion(atElapsed: Double(step) * 0.1)
            #expect(value <= previous + 1e-12)
            previous = value
        }
    }

    @Test func expansionIsContinuousAcrossPhaseBoundaries() {
        for boundary in [4.0, 10.0, 14.0, 20.0] {
            let before = BreathingCycle.expansion(atElapsed: boundary - 0.001)
            let after = BreathingCycle.expansion(atElapsed: boundary + 0.001)
            #expect(abs(before - after) < 0.001)
        }
    }

    @Test func negativeAndNonFiniteInputsAreSafe() {
        #expect(BreathingCycle.state(atElapsed: -5).phase == .inhale)
        #expect(BreathingCycle.positionInCycle(.infinity) == 0)
    }

    @Test func nextPhaseChangeFindsTheFollowingBoundary() {
        #expect(BreathingCycle.nextPhaseChange(after: 0) == 4)
        #expect(BreathingCycle.nextPhaseChange(after: 3.9) == 4)
        #expect(BreathingCycle.nextPhaseChange(after: 4) == 10)
        #expect(BreathingCycle.nextPhaseChange(after: 9.5) == 10)
        #expect(BreathingCycle.nextPhaseChange(after: 10) == 14)
        #expect(BreathingCycle.nextPhaseChange(after: 123) == 124)
    }
}
