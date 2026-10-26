import SwiftUI

struct PopoverView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContentUnavailableView {
                Label("No Server Yet", systemImage: "server.rack")
            } description: {
                Text("Add a Glances 5 server to see its status here.")
            } actions: {
                Button("Add Server…", action: showSettings)
            }

            Divider()

            HStack {
                Button("Open Dashboard", action: showDashboard)
                    .keyboardShortcut("d")
                Spacer()
                Button("Settings…", systemImage: "gearshape", action: showSettings)
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(",")
                Button("Quit", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 340)
    }

    private func showDashboard() {
        openWindow(id: SceneID.dashboard)
        NSApplication.shared.activate()
    }

    private func showSettings() {
        NSApplication.shared.activate()
        openSettings()
    }
}
