import MetriBarKit
import SwiftUI

struct CompactAlertsView: View {
    let monitor: ServerMonitor

    var body: some View {
        let snapshot = monitor.snapshot
        if snapshot.alerts == nil {
            FeedPlaceholder(monitor: monitor, feed: .alerts)
        } else if incidents.isEmpty, events.isEmpty {
            ContentUnavailableView(
                "No Alerts", systemImage: "checkmark.circle",
                description: Text(
                    snapshot.incidents?.isInitializing == true
                        ? String(localized: "Glances is still collecting its first values.")
                        : String(localized: "No value has crossed a Glances threshold recently.")))
        } else {
            VStack(spacing: 20) {
                if !incidents.isEmpty {
                    incidentsSection
                }
                if !events.isEmpty {
                    eventsSection
                }
            }
            .padding()
        }
    }

    private var incidentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Incidents", systemImage: "exclamationmark.triangle")
                .font(.headline)

            ForEach(incidents) { incident in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: incident.ongoing ? "exclamationmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(incident.ongoing ? incident.level.color : .secondary)
                        Text(incident.subject)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        LevelLabel(level: incident.level)
                    }

                    HStack(spacing: 12) {
                        if let begin = incident.beginDate {
                            Text("Started: \(Format.time(begin))")
                        }
                        if incident.ongoing {
                            Text("Ongoing")
                                .foregroundStyle(incident.level.color)
                        } else if let end = incident.endDate {
                            Text("Ended: \(Format.time(end))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    if !incident.top.isEmpty {
                        Text("Top: \(incident.top)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(14)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Event Timeline", systemImage: "clock")
                .font(.headline)

            ForEach(events) { event in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.subject)
                            .font(.subheadline.weight(.medium))
                        Text(Format.time(event.eventDate))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        LevelLabel(level: event.level)
                        if event.value > 0 {
                            Text(Format.number(event.value, fractionDigits: 1))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
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
