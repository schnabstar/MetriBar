#if DEBUG
    import SwiftUI

    /// Development tool for checking windows in the running app with demo
    /// data. Launch with `-MetriBarDemo 1` to use a throwaway model with the
    /// demo server instead of the saved servers, and add
    /// `-MetriBarOpen dashboard,settings,add-server` to open those windows.
    /// `-MetriBarSection processes` and `-MetriBarSettingsTab general` choose
    /// what they show.
    @MainActor
    enum DebugLaunch {
        static func makeModel() -> AppModel? {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "MetriBarDemo") else { return nil }
            let model = SnapshotRenderer.makeModel(suite: "MetriBarDemo")
            model.addDemoServer()
            if let section = defaults.string(forKey: "MetriBarSection").flatMap(DashboardSection.init(rawValue:)) {
                model.dashboardSection = section
            }
            if let tab = defaults.string(forKey: "MetriBarSettingsTab").flatMap(SettingsTab.init(rawValue:)) {
                model.settingsTab = tab
            }
            return model
        }
    }

    /// Opens the windows requested with `-MetriBarOpen`.
    struct DebugWindowOpener: ViewModifier {
        @Environment(AppModel.self) private var model
        @Environment(\.openWindow) private var openWindow
        @Environment(\.openSettings) private var openSettings

        func body(content: Content) -> some View {
            content.task {
                let names = UserDefaults.standard.string(forKey: "MetriBarOpen")?.split(separator: ",") ?? []
                for name in names {
                    switch name {
                    case "dashboard":
                        openWindow(id: SceneID.dashboard)
                    case "settings":
                        openSettings()
                    case "add-server":
                        model.isAddingServer = true
                        openSettings()
                    default:
                        break
                    }
                }
            }
        }
    }
#endif
