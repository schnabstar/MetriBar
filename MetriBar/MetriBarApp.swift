import SwiftUI

@main
struct MetriBarApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
            SnapshotRenderer.runIfRequested()
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Window("MetriBar", id: SceneID.dashboard) {
            DashboardWindow()
                .environment(model)
        }
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

enum SceneID {
    static let dashboard = "dashboard"
}
