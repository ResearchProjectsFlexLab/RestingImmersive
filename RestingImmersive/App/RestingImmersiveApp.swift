import SwiftUI

@main
struct RestingImmersiveApp: App {
    @State private var appModel = AppModel()
    @State private var immersionStyle: ImmersionStyle = .full

    var body: some Scene {
        WindowGroup(id: AppModel.mainWindowID) {
            LaunchView()
                .environment(appModel)
        }
        .defaultSize(width: 560, height: 720)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            SanctuaryView()
                .environment(appModel)
        }
        .immersionStyle(selection: $immersionStyle, in: .full)
        .upperLimbVisibility(.visible)
    }
}
