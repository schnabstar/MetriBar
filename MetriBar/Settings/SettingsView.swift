#if os(macOS)
import SwiftUI

/// One window with one sidebar, like System Settings: the servers, then the
/// display, notification and general settings. "About MetriBar" is the standard About
/// window in the app menu and the menu bar window, not a settings pane.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SettingsSidebar()
                .navigationSplitViewColumnWidth(220)
        } detail: {
            switch model.settingsTab {
            case .servers: ServerSettingsDetail()
            case .display: DisplaySettingsView()
            case .notifications: NotificationSettingsView()
            case .thresholds: ThresholdSettingsView()
            case .general: GeneralSettingsView()
            }
        }
        .frame(width: 760, height: 520)
    }
}
#endif
