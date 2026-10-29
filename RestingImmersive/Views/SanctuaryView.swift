import RealityKit
import SwiftUI

/// The fully immersive sanctuary: the RealityKit environment plus two spatial attachments,
/// a breathing instruction above the orb and a small control panel below it.
struct SanctuaryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scene = SanctuaryScene()
    @State private var soundscape = AmbientSoundscape()

    private var shouldPlaySound: Bool {
        guard appModel.ambientSound else { return false }
        let status = appModel.session.status
        return status == .running || status == .completed
    }

    private enum AttachmentID: String {
        case instruction
        case controls
    }

    var body: some View {
        RealityView { content, attachments in
            await scene.build()
            scene.soundscape = soundscape
            content.add(scene.root)

            if let instruction = attachments.entity(for: AttachmentID.instruction.rawValue) {
                instruction.position = SanctuaryScene.instructionPosition
                scene.root.addChild(instruction)
            }
            if let controls = attachments.entity(for: AttachmentID.controls.rawValue) {
                controls.position = SanctuaryScene.controlsPosition
                // Tilt the panel back so it faces a viewer looking slightly down at it.
                controls.orientation = simd_quatf(angle: -.pi / 10, axis: SIMD3(1, 0, 0))
                scene.root.addChild(controls)
            }

            scene.startUpdating(in: content, session: appModel.session)
            appModel.sanctuaryDidBecomeReady()
        } attachments: {
            Attachment(id: AttachmentID.instruction.rawValue) {
                BreathingInstructionView()
                    .environment(appModel)
            }
            Attachment(id: AttachmentID.controls.rawValue) {
                SessionControlsView()
                    .environment(appModel)
            }
        }
        .onChange(of: reduceMotion, initial: true) { _, newValue in
            scene.setReduceMotion(newValue)
        }
        .onChange(of: shouldPlaySound, initial: true) { _, play in
            soundscape.setPlaying(play)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                appModel.session.handleInterruption()
            }
        }
        .onDisappear {
            scene.stopUpdating()
            soundscape.setPlaying(false)
            appModel.immersiveSpaceDidClose()
            if !appModel.isMainWindowOpen {
                openWindow(id: AppModel.mainWindowID)
            }
        }
    }
}
