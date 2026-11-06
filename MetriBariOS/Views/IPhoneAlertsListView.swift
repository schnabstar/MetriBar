import MetriBarKit
import SwiftUI

struct IPhoneAlertsListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if ongoingAlerts.isEmpty && firingRules.isEmpty {
                ContentUnavailableView {
                    Label("All Systems Normal", systemImage: "checkmark.shield")
                } description: {
                    Text("No servers report active incidents or threshold violations.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !firingRules.isEmpty {
                Section("Active Threshold Rules") {
                    ForEach(firingRules, id: \.id) { rule in
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .symbolRenderingMode(.multicolor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RuleText.summary(rule))
                                    .font(.subheadline.weight(.medium))
                                Text(serverName(for: rule.serverID))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !ongoingAlerts.isEmpty {
                Section("Server Incidents") {
                    ForEach(ongoingAlerts, id: \.uniqueID) { item in
                        HStack(spacing: 12) {
                            LevelLabel(level: item.incident.level ?? .warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AlertText.subject(
                                    plugin: item.incident.plugin,
                                    field: item.incident.field,
                                    key: item.incident.key
                                ))
                                .font(.subheadline.weight(.medium))

                                HStack(spacing: 6) {
                                    Text(item.serverName)
                                    if let begin = item.incident.beginDate {
                                        Text("•")
                                        Text(Format.time(begin))
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { model.center.refreshAll() }
        .navigationTitle("Alerts")
    }

    private struct ServerAlertItem {
        let uniqueID: String
        let serverName: String
        let incident: AlertIncident
    }

    private var ongoingAlerts: [ServerAlertItem] {
        var items: [ServerAlertItem] = []
        for monitor in model.center.monitors {
            for (idx, incident) in (monitor.snapshot.incidents?.incidents ?? []).enumerated() {
                if incident.ongoing == true {
                    items.append(ServerAlertItem(
                        uniqueID: "\(monitor.id)-\(idx)",
                        serverName: monitor.displayName,
                        incident: incident
                    ))
                }
            }
        }
        return items
    }

    private var firingRules: [ThresholdRule] {
        // Collect rules currently firing
        model.rules.filter { rule in
            if let serverID = rule.serverID {
                return model.center.monitors.first(where: { $0.id == serverID })?.health == .warning ||
                       model.center.monitors.first(where: { $0.id == serverID })?.health == .critical
            }
            return model.center.health == .warning || model.center.health == .critical
        }
    }

    private func serverName(for id: UUID?) -> String {
        guard let id else { return String(localized: "All Servers") }
        return model.servers.first(where: { $0.id == id })?.displayName ?? String(localized: "Unknown Server")
    }
}
