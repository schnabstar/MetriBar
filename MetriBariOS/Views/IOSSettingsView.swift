import MetriBarKit
import SwiftUI

struct IOSSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showsAddServer = false

    var body: some View {
        Form {
            Section("Servers") {
                ForEach(model.servers) { config in
                    NavigationLink {
                        ServerDetailSettingsView(serverID: config.id)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(config.isEnabled ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(config.displayName)
                                    .font(.body)
                                Text(config.url.host ?? config.url.absoluteString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        model.remove(model.servers[index].id)
                    }
                }

                Button {
                    showsAddServer = true
                } label: {
                    Label("Add Server…", systemImage: "plus")
                }
            }

            Section {
                Picker("In the background", selection: baseBinding) {
                    ForEach(Preferences.baseIntervalChoices, id: \.self) { seconds in
                        Text("Every \(seconds) seconds").tag(seconds)
                    }
                }
                Picker("While active", selection: liveBinding) {
                    ForEach(Preferences.liveIntervalChoices, id: \.self) { seconds in
                        Text(
                            seconds == 1
                                ? String(localized: "Every second")
                                : String(localized: "Every \(seconds) seconds")
                        )
                        .tag(seconds)
                    }
                }
            } header: {
                Text("Refresh Intervals")
            } footer: {
                Text("MetriBar polls your servers directly. It collects no telemetry and sends nothing to anyone.")
            }

            Section("Alerts & Thresholds") {
                NavigationLink {
                    NotificationSettingsView()
                        .navigationTitle("Notifications")
                } label: {
                    Label("Notifications", systemImage: "bell")
                }

                NavigationLink {
                    ThresholdSettingsView()
                        .navigationTitle("Threshold Rules")
                } label: {
                    Label("Threshold Rules", systemImage: "slider.horizontal.3")
                }
            }

            Section("Privacy & Permissions") {
                Button {
                    openURL(LocalNetworkCheck.settingsURL)
                } label: {
                    HStack {
                        Text("Local Network Permission")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("About") {
                LabeledContent("App Version", value: AppModel.currentVersion.description)
                Link(destination: URL(string: "https://github.com/schnabstar/MetriBar")!) {
                    HStack {
                        Text("MetriBar on GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundStyle(.secondary)
                    }
                }
                Link(destination: URL(string: "https://github.com/schnabstar/MetriBar/issues")!) {
                    HStack {
                        Text("Report an Issue")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showsAddServer) {
            AddServerSheet()
        }
    }

    private var baseBinding: Binding<Int> {
        Binding(
            get: { model.preferences.baseIntervalSeconds },
            set: { value in model.update { $0.baseIntervalSeconds = value } }
        )
    }

    private var liveBinding: Binding<Int> {
        Binding(
            get: { model.preferences.liveIntervalSeconds },
            set: { value in model.update { $0.liveIntervalSeconds = value } }
        )
    }
}

private struct ServerDetailSettingsView: View {
    let serverID: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        ServerEditorView(mode: .edit(serverID))
            .navigationTitle(model.servers.first(where: { $0.id == serverID })?.displayName ?? "Server")
    }
}
