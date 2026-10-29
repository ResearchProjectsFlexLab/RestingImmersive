import SwiftUI
import UIKit

/// The floating cue above the orb. Shows nothing when guided breathing is off.
struct BreathingInstructionView: View {
    @Environment(AppModel.self) private var appModel

    private var session: MeditationSession { appModel.session }

    var body: some View {
        ZStack {
            if let text = displayedText {
                Text(text)
                    .id(text)
                    .font(.system(size: 52, weight: .light, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: Palette.cyan.opacity(0.55), radius: 16)
                    // Fade the old cue out before the new one appears so they never overlap.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeInOut(duration: 0.6).delay(0.35)),
                        removal: .opacity.animation(.easeOut(duration: 0.35))
                    ))
            }
        }
        .frame(width: 560, height: 100)
        .animation(.easeInOut(duration: 0.6), value: displayedText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Breathing guidance")
        .accessibilityValue(displayedText ?? "")
        .accessibilityHidden(displayedText == nil)
        .onChange(of: session.breathingPhase) { _, phase in
            guard let phase, UIAccessibility.isVoiceOverRunning else { return }
            AccessibilityNotification.Announcement(phase.instruction).post()
        }
    }

    private var displayedText: String? {
        guard session.configuration.guidedBreathing else { return nil }
        switch session.status {
        case .running: return session.breathingPhase?.instruction
        case .paused: return String(localized: "Paused")
        default: return nil
        }
    }
}
