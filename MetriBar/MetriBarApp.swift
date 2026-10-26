import SwiftUI

@main
struct MetriBarApp: App {
    var body: some Scene {
        MenuBarExtra {
            PopoverView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("MetriBar", id: SceneID.dashboard) {
            DashboardWindow()
        }
        .defaultSize(width: 980, height: 640)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
        }
    }
}

enum SceneID {
    static let dashboard = "dashboard"
}
