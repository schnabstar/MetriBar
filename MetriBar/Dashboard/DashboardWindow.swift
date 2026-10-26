import SwiftUI

struct DashboardWindow: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("No servers")
                    .foregroundStyle(.secondary)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            ContentUnavailableView(
                "No Server Selected",
                systemImage: "server.rack",
                description: Text("Add a Glances 5 server in Settings.")
            )
        }
        .onAppear(perform: DockPresence.show)
        .onDisappear(perform: DockPresence.hide)
    }
}

/// MetriBar is a menu bar app without a Dock icon. While the dashboard is
/// open it becomes a regular app so the window shows up in the Dock and in
/// the app switcher.
enum DockPresence {
    static func show() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    static func hide() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
