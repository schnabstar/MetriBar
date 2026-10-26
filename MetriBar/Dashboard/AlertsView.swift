import MetriBarKit
import SwiftUI

/// Incidents and the events behind them, as two sortable tables.
struct AlertsView: View {
    let monitor: ServerMonitor

    /// Ongoing incidents first, then the most recent.
    @State private var incidentOrder = [
        KeyPathComparator(\IncidentTableRow.rank), KeyPathComparator(\IncidentTableRow.begin, order: .reverse),
    ]
    @State private var eventOrder = [KeyPathComparator(\EventTableRow.date, order: .reverse)]

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
            VSplitView {
                Table(incidents.sorted(using: incidentOrder), sortOrder: $incidentOrder) {
                    TableColumn("Incident", value: \.subject) { row in
                        Label {
                            Text(row.subject)
                                .fontWeight(row.ongoing ? .semibold : .regular)
                        } icon: {
                            Image(systemName: row.ongoing ? "exclamationmark.circle.fill" : "checkmark.circle")
                                .foregroundStyle(row.ongoing ? row.level.color : .secondary)
                        }
                    }
                    TableColumn("Level", value: \.level) { LevelLabel(level: $0.level) }
                        .width(min: 80, ideal: 100)
                    TableColumn("Start", value: \.begin) { Text(Format.time($0.beginDate)) }
                        .width(min: 70, ideal: 90)
                    TableColumn("End", value: \.end) { row in
                        Text(row.ongoing ? String(localized: "ongoing") : Format.time(row.endDate))
                            .foregroundStyle(row.ongoing ? .secondary : .primary)
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Top Processes", value: \.top)
                }
                .overlay {
                    if incidents.isEmpty {
                        Text("No incidents.").foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 100, idealHeight: 180)
                Table(events.sorted(using: eventOrder), sortOrder: $eventOrder) {
                    TableColumn("Time", value: \.date) { Text(Format.time($0.eventDate)) }
                        .width(min: 70, ideal: 90)
                    TableColumn("Event", value: \.subject)
                    TableColumn("Level", value: \.level) { LevelLabel(level: $0.level) }
                        .width(min: 80, ideal: 100)
                    TableColumn("Previous Level", value: \.previousLevel) {
                        Text(AlertText.level($0.previousLevel)).foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn("Value", value: \.value) { Text(Format.number($0.value, fractionDigits: 1)) }
                        .width(min: 50, ideal: 70)
                        .alignment(.numeric)
                }
                .frame(minHeight: 100)
            }
            .monospacedDigit()
            .scrollEdgeEffectStyle(.hard, for: .top)
        }
    }

    private var incidents: [IncidentTableRow] {
        (monitor.snapshot.incidents?.incidents ?? []).enumerated().map {
            IncidentTableRow(index: $0.offset, incident: $0.element)
        }
    }

    private var events: [EventTableRow] {
        (monitor.snapshot.alerts ?? []).enumerated().map { EventTableRow(index: $0.offset, event: $0.element) }
    }
}

/// Plain data for the table; `nonisolated` so its key paths are `Sendable`
/// for `KeyPathComparator` despite the app's `MainActor` default isolation.
nonisolated struct IncidentTableRow: Identifiable, Sendable {
    let id: Int
    let subject: String
    let level: Level
    let ongoing: Bool
    /// 0 for ongoing incidents, so they sort first.
    let rank: Int
    let beginDate: Date?
    let endDate: Date?
    let top: String

    init(index: Int, incident: AlertIncident) {
        id = index
        subject = AlertText.subject(plugin: incident.plugin, field: incident.field, key: incident.key)
        level = incident.level ?? .unknown
        ongoing = incident.ongoing == true
        rank = ongoing ? 0 : 1
        beginDate = incident.beginDate
        endDate = incident.endDate
        top = (incident.top ?? []).joined(separator: ", ")
    }

    var begin: Date { beginDate ?? .distantPast }
    var end: Date { ongoing ? .distantFuture : endDate ?? .distantPast }
}

/// Plain data for the table; `nonisolated` so its key paths are `Sendable`
/// for `KeyPathComparator` despite the app's `MainActor` default isolation.
nonisolated struct EventTableRow: Identifiable, Sendable {
    let id: Int
    let eventDate: Date?
    let subject: String
    let level: Level
    let previousLevel: Level
    let value: Double

    init(index: Int, event: AlertEvent) {
        id = index
        eventDate = event.date
        subject = AlertText.subject(plugin: event.plugin, field: event.field, key: event.key)
        level = event.level ?? .unknown
        previousLevel = event.previousLevel ?? .unknown
        // Not finite when missing: sorts last and shows a dash.
        value = event.value ?? -.infinity
    }

    var date: Date { eventDate ?? .distantPast }
}

/// An incident in the overview card.
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
            LevelLabel(level: incident.level)
                .font(.caption)
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

nonisolated enum AlertText {
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
}
