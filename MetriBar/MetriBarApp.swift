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
        .defaultSize(width: 980, height: 640)
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
