import Foundation

/// The guided breathing pattern: a 4 second inhale followed by a 6 second exhale.
///
/// Everything here is a pure function of elapsed session time, so the on-screen
/// instruction and the orb's motion can never drift apart.
enum BreathingPhase: String, Equatable, Sendable {
    case inhale
    case exhale

    var instruction: String {
        switch self {
        case .inhale: String(localized: "Breathe in")
        case .exhale: String(localized: "Breathe out")
        }
    }
}

struct BreathingState: Equatable, Sendable {
    var phase: BreathingPhase
    /// Linear progress through the current phase, in `0..<1`.
    var progress: Double
    /// Seconds left before the next phase begins.
    var secondsRemainingInPhase: Double
}

enum BreathingCycle {
    static let inhaleDuration: TimeInterval = 4
    static let exhaleDuration: TimeInterval = 6
    static let cycleDuration: TimeInterval = inhaleDuration + exhaleDuration

    static func state(atElapsed elapsed: TimeInterval) -> BreathingState {
        let position = positionInCycle(elapsed)
        if position < inhaleDuration {
            return BreathingState(
                phase: .inhale,
                progress: position / inhaleDuration,
                secondsRemainingInPhase: inhaleDuration - position
            )
        } else {
            let exhalePosition = position - inhaleDuration
            return BreathingState(
                phase: .exhale,
                progress: exhalePosition / exhaleDuration,
                secondsRemainingInPhase: exhaleDuration - exhalePosition
            )
        }
    }

    /// How "full" the breath is at a given moment: 0 at the bottom of an exhale,
    /// 1 at the top of an inhale. Eased so the orb never changes direction abruptly.
    static func expansion(atElapsed elapsed: TimeInterval) -> Double {
        let state = state(atElapsed: elapsed)
        let eased = easeInOut(state.progress)
        switch state.phase {
        case .inhale: return eased
        case .exhale: return 1 - eased
        }
    }

    static func positionInCycle(_ elapsed: TimeInterval) -> TimeInterval {
        let clamped = max(0, elapsed)
        let position = clamped.truncatingRemainder(dividingBy: cycleDuration)
        return position.isFinite ? position : 0
    }

    /// Sinusoidal ease with zero velocity at both ends.
    static func easeInOut(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return 0.5 - 0.5 * cos(.pi * t)
    }
}
