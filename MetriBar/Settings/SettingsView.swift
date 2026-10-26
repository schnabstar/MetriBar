import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Servers", systemImage: "server.rack") {
                placeholder("Configured Glances servers will appear here.")
            }
            Tab("Display", systemImage: "menubar.rectangle") {
                placeholder("Choose what the menu bar shows.")
            }
            Tab("General", systemImage: "gearshape") {
                placeholder("Refresh intervals and launch at login.")
            }
            Tab("About", systemImage: "info.circle") {
                AboutView()
            }
        }
        .frame(width: 520, height: 360)
    }

    private func placeholder(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
