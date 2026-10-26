import MetriBarKit
import SwiftUI

struct AlertsView: View {
    let monitor: ServerMonitor

    var body: some View {
        if monitor.snapshot.alerts == nil {
            FeedPlaceholder(monitor: monitor, feed: .alerts)
        } else if incidents.isEmpty, events.isEmpty {
            ContentUnavailableView(
                "No Alerts", systemImage: "checkmark.circle",
                description: Text(
                    monitor.snapshot.incidents?.isInitializing == true
                        ? String(localized: "Glances is still collecting its first values.")
                        : String(localized: "No value has crossed a Glances threshold recently.")))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashboardGroup(title: String(localized: "Incidents")) {
                        if incidents.isEmpty {
                            Text("No incidents.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(incidents.enumerated()), id: \.offset) { _, incident in
                            IncidentRow(incident: incident)
                        }
                    }
                    DashboardGroup(title: String(localized: "Events")) {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            ForEach(Array(events.reversed().enumerated()), id: \.offset) { _, event in
                                GridRow {
                                    Text(Format.time(event.date))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                    Text(AlertText.subject(plugin: event.plugin, field: event.field, key: event.key))
                                    Text(AlertText.transition(from: event.previousLevel, to: event.level))
                                        .foregroundStyle((event.level ?? .unknown).color)
                                    Text(event.value.map { Format.number($0, fractionDigits: 1) } ?? "")
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    /// Ongoing incidents first, then the most recent.
    private var incidents: [AlertIncident] {
        (monitor.snapshot.incidents?.incidents ?? []).sorted { lhs, rhs in
            if (lhs.ongoing ?? false) != (rhs.ongoing ?? false) { return lhs.ongoing ?? false }
            return (lhs.beginDate ?? .distantPast) > (rhs.beginDate ?? .distantPast)
        }
    }

    private var events: [AlertEvent] {
        monitor.snapshot.alerts ?? []
    }
}

struct IncidentRow: View {
    let incident: AlertIncident

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: incident.ongoing == true ? "exclamationmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(incident.ongoing == true ? (incident.level ?? .unknown).color : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(AlertText.subject(plugin: incident.plugin, field: incident.field, key: incident.key))
                    .fontWeight(incident.ongoing == true ? .semibold : .regular)
                Text(timing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let top = incident.top, !top.isEmpty {
                    Text("Top processes: \(top.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(AlertText.level(incident.level))
                .font(.caption.weight(.semibold))
                .foregroundStyle((incident.level ?? .unknown).color)
        }
        .accessibilityElement(children: .combine)
    }

    private var timing: String {
        let begin = incident.beginDate.map(Format.time) ?? String(localized: "unknown start")
        if incident.ongoing == true {
            return String(localized: "Since \(begin)")
        }
        let end = incident.endDate.map(Format.time) ?? String(localized: "unknown end")
        return "\(begin) – \(end)"
    }
}

enum AlertText {
    /// "fs /mnt/data · percent" style description.
    static func subject(plugin: String?, field: String?, key: String?) -> String {
        [plugin, key, field].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func level(_ level: Level?) -> String {
        switch level ?? .unknown {
        case .unknown: String(localized: "unknown")
        case .ok: String(localized: "ok")
        case .careful: String(localized: "careful")
        case .warning: String(localized: "warning")
        case .critical: String(localized: "critical")
        }
    }

    static func transition(from previous: Level?, to level: Level?) -> String {
        "\(Self.level(previous)) → \(Self.level(level))"
    }
}
