import SwiftUI

/// The compact glass panel below the orb: countdown, pause/resume, and end.
struct SessionControlsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var isLeaving = false

    private var session: MeditationSession { appModel.session }

    var body: some View {
        VStack(spacing: 18) {
            if session.status == .completed {
                completion
            } else {
                countdown
                if session.wasInterrupted {
                    Text("Paused while you were away")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                buttons
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(minWidth: 340)
        .glassBackgroundEffect()
        .animation(.easeInOut(duration: 0.4), value: session.status)
    }

    private var countdown: some View {
        Text(TimeFormatting.countdown(session.remainingSeconds))
            .font(.system(size: 54, weight: .light, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .accessibilityLabel("Time remaining")
            .accessibilityValue(TimeFormatting.spokenDuration(TimeInterval(session.remainingSeconds)))
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var buttons: some View {
        HStack(spacing: 16) {
            Button {
                session.togglePause()
            } label: {
                Label(
                    session.status == .paused ? "Resume" : "Pause",
                    systemImage: session.status == .paused ? "play.fill" : "pause.fill"
                )
                .frame(minWidth: 110)
            }
            .disabled(!session.isActive || isLeaving)

            Button {
                appModel.ambientSound.toggle()
            } label: {
                Label(
                    appModel.ambientSound ? "Mute sound" : "Play sound",
                    systemImage: appModel.ambientSound ? "speaker.wave.2.fill" : "speaker.slash.fill"
                )
                .labelStyle(.iconOnly)
            }
            .help(appModel.ambientSound ? "Mute sound" : "Play sound")

            Button {
                Task { await leave() }
            } label: {
                Label("End", systemImage: "xmark")
                    .frame(minWidth: 90)
            }
            .disabled(isLeaving)
            .accessibilityHint("Ends the session and leaves the sanctuary.")
        }
        .controlSize(.large)
    }

    private var completion: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.cyan)
                .accessibilityHidden(true)
            Text("Session complete")
                .font(.title2.weight(.light))
            Text("Take a moment before you return.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                Task { await leave() }
            } label: {
                Label("Return", systemImage: "arrow.uturn.backward")
                    .frame(minWidth: 140)
            }
            .controlSize(.large)
            .disabled(isLeaving)
        }
    }

    private func leave() async {
        guard !isLeaving else { return }
        isLeaving = true
        appModel.beginClosing()
        // Dismiss unconditionally: if state and presentation ever disagree, this
        // still removes the space rather than leaving the user stranded in it.
        await dismissImmersiveSpace()
        if appModel.immersiveSpaceState != .closed {
            appModel.immersiveSpaceDidClose()
        }
        isLeaving = false
    }
}
