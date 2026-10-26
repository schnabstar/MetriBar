import SwiftUI

@main
struct MetriBarApp: App {
    @State private var model: AppModel

    init() {
        #if DEBUG
            SnapshotRenderer.runIfRequested()
            _model = State(initialValue: DebugLaunch.makeModel() ?? AppModel())
        #else
            _model = State(initialValue: AppModel())
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(model)
        } label: {
            MenuBarLabel()
                #if DEBUG
                    .modifier(DebugWindowOpener())
                #endif
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
        .commands {
            AppCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

enum SceneID {
    static let dashboard = "dashboard"
}
