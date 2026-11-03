import SwiftUI

@main
struct MetriBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        #if DEBUG
            SnapshotRenderer.runIfRequested()
            let model = DebugLaunch.makeModel() ?? AppModel()
        #else
            let model = AppModel()
        #endif
        _model = State(initialValue: model)
        AppDelegate.openURL = { [weak model] url in model?.open(url) }
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
