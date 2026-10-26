import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Tab("Servers", systemImage: "server.rack", value: SettingsTab.servers) {
                ServersSettingsView()
            }
            Tab("Display", systemImage: "menubar.rectangle", value: SettingsTab.display) {
                DisplaySettingsView()
            }
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView()
            }
            Tab("About", systemImage: "info.circle", value: SettingsTab.about) {
                AboutView()
            }
        }
        .frame(width: 720, height: 540)
    }
}
