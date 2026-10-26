import MetriBarKit
import SwiftUI

struct ServersSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmRemoval = false

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $model.editingServerID) {
                    ForEach(model.servers) { config in
                        ServerRow(config: config, health: model.center.monitor(for: config.id)?.health ?? .unknown)
                            .tag(config.id)
                            .contextMenu {
                                Button("Remove Server…", role: .destructive) {
                                    model.editingServerID = config.id
                                    confirmRemoval = true
                                }
                            }
                    }
                    .onMove { model.move(fromOffsets: $0, toOffset: $1) }
                }
                .onDeleteCommand {
                    if model.editingServerID != nil { confirmRemoval = true }
                }
                Divider()
                HStack(spacing: 2) {
                    Button("Add Server", systemImage: "plus") { model.isAddingServer = true }
                        .frame(width: 24, height: 22)
                        .help("Add Server")
                    Button("Remove Server", systemImage: "minus") { confirmRemoval = true }
                        .frame(width: 24, height: 22)
                        .help("Remove Server")
                        .disabled(model.editingServerID == nil)
                    Spacer()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 220)

            Divider()

            Group {
                if let id = model.editingServerID, model.server(id) != nil {
                    ServerEditorView(mode: .edit(id)).id(id)
                } else {
                    ContentUnavailableView(
                        "No Server Selected", systemImage: "server.rack",
                        description: Text("Select a server or add one with +."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $model.isAddingServer) {
            ServerEditorView(mode: .add) { model.isAddingServer = false }
                // Standard form sheet, as tall as the form needs.
                .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        }
        .confirmationDialog(removalTitle, isPresented: $confirmRemoval) {
            Button("Remove", role: .destructive) {
                if let id = model.editingServerID { model.remove(id) }
            }
        } message: {
            Text("MetriBar forgets the server and deletes its saved password.")
        }
        .onAppear {
            if model.editingServerID == nil { model.editingServerID = model.servers.first?.id }
        }
    }

    private var removalTitle: String {
        let name = model.editingServerID.flatMap(model.server)?.displayName ?? ""
        return String(localized: "Remove “\(name)”?")
    }
}

private struct ServerRow: View {
    let config: ServerConfig
    let health: ServerHealth

    var body: some View {
        HStack(spacing: 8) {
            HealthBadge(health: config.isEnabled ? health : .unknown)
            VStack(alignment: .leading, spacing: 1) {
                Text(config.displayName).lineLimit(1)
                Text(config.url.host() ?? config.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .opacity(config.isEnabled ? 1 : 0.5)
        }
        .padding(.vertical, 2)
    }
}
