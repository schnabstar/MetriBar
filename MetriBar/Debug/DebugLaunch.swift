#if DEBUG
    import MetriBarKit
    import SwiftUI

    /// Development tool for checking windows in the running app with demo
    /// data. Launch with `-MetriBarDemo 1` to use a throwaway model with the
    /// demo server instead of the saved servers, and add
    /// `-MetriBarOpen dashboard,settings,add-server` to open those windows.
    /// `-MetriBarSection processes` and `-MetriBarSettingsTab general` choose
    /// what they show. `-MetriBarFakeUpdate 1` pretends that a newer release
    /// exists, without contacting GitHub. `-MetriBarFakeNotification 1` sends
    /// a notification about a critical CPU of the demo server.
    /// `-MetriBarFakeRule 1` adds a rule that fires on the demo server.
    /// `-MetriBarMenuBar cpu,memory,networkDown` shows those values in the
    /// menu bar, `-MetriBarMenuBarStyle labels|symbols|valuesOnly` sets the style,
    /// `-MetriBarMenuBarTrend 1` adds the trend line.
    @MainActor
    enum DebugLaunch {
        static func makeModel() -> AppModel? {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "MetriBarDemo") else { return nil }
            let fakeNotification = defaults.bool(forKey: "MetriBarFakeNotification")
            let model = SnapshotRenderer.makeModel(suite: "MetriBarDemo", deliversNotifications: fakeNotification)
            model.addDemoServer()
            if fakeNotification {
                let demo = DemoServer.config()
                Task {
                    await model.notifier.requestAuthorization()
                    model.notifier.post([
                        AlertNotice(
                            serverID: demo.id, serverName: demo.displayName, event: .raised,
                            condition: Condition(.cpu, level: .critical, value: 97))
                    ])
                }
            }
            if defaults.bool(forKey: "MetriBarFakeUpdate") { model.updates.showFakeUpdate() }
            if let names = defaults.string(forKey: "MetriBarMenuBar") {
                // `-MetriBarMenuBar cpu,memory,networkDown -MetriBarMenuBarStyle labels`
                let items = names.split(separator: ",").compactMap { MenuBarMetric(rawValue: String($0)) }
                let style = defaults.string(forKey: "MetriBarMenuBarStyle").flatMap(MenuBarStyle.init(rawValue:))
                model.update {
                    $0.menuBarItems = Preferences.normalized(items)
                    if let style { $0.menuBarStyle = style }
                    $0.menuBarTrend = defaults.bool(forKey: "MetriBarMenuBarTrend")
                }
            }
            if defaults.bool(forKey: "MetriBarFakeRule") {
                model.saveRule(ThresholdRule(metric: RuleMetric(.cpu), limit: 5, severity: .critical))
            }
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
