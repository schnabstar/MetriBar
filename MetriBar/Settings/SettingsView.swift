import SwiftUI

/// Each tab has its own size, so the window fits the pane like the settings
/// of Apple's apps. "About MetriBar" is the standard About window in the
/// app menu and the menu bar window, not a settings tab.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Tab("Servers", systemImage: "server.rack", value: SettingsTab.servers) {
                ServersSettingsView()
                    .frame(width: 720, height: 500)
            }
            Tab("Display", systemImage: "menubar.rectangle", value: SettingsTab.display) {
                DisplaySettingsView()
                    .frame(width: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView()
                    .frame(width: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
