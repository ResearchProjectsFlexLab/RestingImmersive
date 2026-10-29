import SwiftUI

/// The single entry window: choose a length, optionally enable guided breathing, and enter.
struct LaunchView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var appModel = appModel

        VStack(spacing: 32) {
            header

            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Length")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Picker("Session length", selection: $appModel.selectedMinutes) {
                        ForEach(AppModel.durationOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle(isOn: $appModel.guidedBreathing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Guided breathing")
                            .font(.headline)
                        Text("Breathe in for 4 seconds, out for 6.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $appModel.ambientSound) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ambient sound")
                            .font(.headline)
                        Text("A soft drone tuned to 432 Hz that swells with your breath.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(24)
            .background(.regularMaterial, in: .rect(cornerRadius: 28))

            VStack(spacing: 14) {
                Button {
                    Task { await enterSanctuary() }
                } label: {
                    Label(
                        appModel.immersiveSpaceState == .opening ? "Opening…" : "Enter Sanctuary",
                        systemImage: "sparkles"
                    )
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.cyan)
                .controlSize(.extraLarge)
                .disabled(!appModel.canBeginSession)
                .accessibilityHint("Opens a fully immersive space for your meditation.")

                statusMessage
            }
        }
        .padding(40)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640, minHeight: 640, idealHeight: 720)
        .onAppear { appModel.isMainWindowOpen = true }
        .onDisappear { appModel.isMainWindowOpen = false }
        #if DEBUG
        .task {
            // Lets the simulator be verified without pointer input:
            // `simctl launch <device> <bundle> -autoEnterSanctuary [-unguided]`
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("-autoEnterSanctuary"), appModel.lastOutcome == nil else { return }
            if arguments.contains("-unguided") { appModel.guidedBreathing = false }
            if arguments.contains("-oneMinute") { appModel.selectedMinutes = 1 }
            await enterSanctuary()
        }
        #endif
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.cyan, Palette.lavender)
                .accessibilityHidden(true)
            Text("Resting")
                .font(.system(size: 52, weight: .thin, design: .rounded))
            Text("A quiet sanctuary for a few unhurried breaths.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let message = appModel.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        } else if let outcome = appModel.lastOutcome {
            Text(outcomeText(outcome))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            // Reserve space so the layout doesn't jump when a message appears.
            Text(" ").font(.callout).accessibilityHidden(true)
        }
    }

    private func outcomeText(_ outcome: AppModel.SessionOutcome) -> String {
        switch outcome {
        case .completed(let duration):
            String(localized: "Session complete — \(TimeFormatting.spokenDuration(duration)) of rest.")
        case .endedEarly(let elapsed):
            String(localized: "Session ended after \(TimeFormatting.spokenDuration(elapsed)).")
        }
    }

    private func enterSanctuary() async {
        guard appModel.beginOpening() else { return }
        switch await openImmersiveSpace(id: AppModel.immersiveSpaceID) {
        case .opened:
            appModel.didOpenImmersiveSpace()
            // Full immersion: step the window aside so the sanctuary is uninterrupted.
            dismissWindow(id: AppModel.mainWindowID)
        case .userCancelled:
            appModel.didFailToOpenImmersiveSpace(userCancelled: true)
        case .error:
            appModel.didFailToOpenImmersiveSpace(userCancelled: false)
        @unknown default:
            appModel.didFailToOpenImmersiveSpace(userCancelled: false)
        }
    }
}

#Preview(windowStyle: .automatic) {
    LaunchView()
        .environment(AppModel())
}
