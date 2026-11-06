import MetriBarKit
import SwiftUI

struct IPhoneServerListView: View {
    @Environment(AppModel.self) private var model
    @State private var showsAddServer = false
    @State private var editingServerID: UUID?

    var body: some View {
        Group {
            if model.center.monitors.isEmpty {
                ContentUnavailableView {
                    Label("No Servers", systemImage: "server.rack")
                } description: {
                    Text("Add a Glances 5 server to see its metrics and status here.")
                } actions: {
                    Button("Add Server…") { showsAddServer = true }
                        .buttonStyle(.borderedProminent)
                    Button("Try with Demo Data") { model.addDemoServer() }
                        .buttonStyle(.bordered)
                }
            } else {
                List {
                    ForEach(model.center.monitors) { monitor in
                        NavigationLink(value: monitor.id) {
                            ServerCardRow(monitor: monitor)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                model.remove(monitor.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                toggleMute(monitor.id)
                            } label: {
                                Label(
                                    monitor.config.notificationsEnabled ? "Mute" : "Unmute",
                                    systemImage: monitor.config.notificationsEnabled ? "bell.slash" : "bell"
                                )
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingServerID = monitor.id
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button("Edit Server…", systemImage: "pencil") {
                                editingServerID = monitor.id
                            }
                            if let url = monitor.config.url.webURL {
                                Link(destination: url) {
                                    Label("Open Web Interface", systemImage: "safari")
                                }
                            }
                            Button("Copy Address", systemImage: "doc.on.doc") {
                                Clipboard.copy(monitor.config.url.absoluteString)
                            }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                model.remove(monitor.id)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    for monitor in model.center.monitors { monitor.refresh() }
                }
            }
        }
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Server")
            }
        }
        .sheet(isPresented: $showsAddServer) {
            AddServerSheet()
        }
        .sheet(isPresented: editingServerSheet) {
            if let editingServerID {
                AddServerSheet(editingServerID: editingServerID)
            }
        }
    }

    private var editingServerSheet: Binding<Bool> {
        Binding(
            get: { editingServerID != nil },
            set: { if !$0 { editingServerID = nil } }
        )
    }

    private func toggleMute(_ id: UUID) {
        guard let config = model.servers.first(where: { $0.id == id }) else { return }
        var updated = config
        updated.notificationsEnabled.toggle()
        try? model.save(updated, password: .keep)
    }
}

private struct ServerCardRow: View {
    let monitor: ServerMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HealthBadge(health: monitor.config.isEnabled ? monitor.health : .unknown)
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(monitor.config.url.host ?? monitor.config.url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !monitor.config.isEnabled {
                    Text("Paused")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: Capsule())
                        .foregroundStyle(.secondary)
                } else if monitor.isStale {
                    Text("Retrying…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if monitor.config.isEnabled && monitor.health != .offline {
                let snapshot = monitor.snapshot
                HStack(spacing: 12) {
                    metricPill(label: "CPU", value: Format.percent(snapshot.cpu?.value.total), level: snapshot.cpu?.worstLevel)
                    metricPill(label: "Mem", value: Format.percent(snapshot.memory?.value.percent), level: snapshot.memory?.worstLevel)
                    if let fs = fullestDisk(snapshot) {
                        metricPill(label: "Disk", value: Format.percent(fs.percent), level: fs.level)
                    }
                    if let temp = hottestTemp(snapshot) {
                        metricPill(label: "Temp", value: Format.temperature(temp.value, unit: temp.unit), level: temp.level)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func metricPill(label: String, value: String, level: Level?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(level?.color ?? .primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func fullestDisk(_ snapshot: ServerSnapshot) -> (percent: Double, level: Level)? {
        guard let items = snapshot.fileSystems?.items, !items.isEmpty else { return nil }
        guard let maxItem = items.max(by: { ($0.percent ?? 0) < ($1.percent ?? 0) }) else { return nil }
        let percent = maxItem.percent ?? 0
        let level = snapshot.fileSystems?.level("percent", item: maxItem.mntPoint ?? "") ?? .unknown
        return (percent, level)
    }

    private func hottestTemp(_ snapshot: ServerSnapshot) -> (value: Double, unit: String?, level: Level)? {
        guard let items = snapshot.sensors?.items else { return nil }
        let temps = items.filter { $0.kind == .temperature }
        guard let maxTemp = temps.max(by: { ($0.value ?? 0) < ($1.value ?? 0) }) else { return nil }
        return (maxTemp.value ?? 0, maxTemp.unit, maxTemp.level)
    }
}

