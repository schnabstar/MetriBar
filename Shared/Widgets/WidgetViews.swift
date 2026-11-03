import MetriBarKit
import SwiftUI
import WidgetKit

nonisolated struct ServerEntry: TimelineEntry {
    let date: Date
    /// `nil` before MetriBar has written anything.
    let snapshot: WidgetSnapshot?
    /// The server chosen in the widget's settings, if any.
    let serverID: UUID?

    /// The chosen server, or the first one.
    var server: WidgetSnapshot.Server? {
        guard let snapshot else { return nil }
        return serverID.flatMap(snapshot.server) ?? snapshot.servers.first
    }

    static let placeholder = ServerEntry(date: .now, snapshot: sample, serverID: nil)

    private static var sample: WidgetSnapshot {
        WidgetSnapshot(
            generated: .now,
            servers: [
                WidgetSnapshot.Server(
                    id: UUID(), name: "Home Server", health: .ok, cpu: 18, memory: 54, disk: 63, temperature: 47,
                    updated: .now),
                WidgetSnapshot.Server(
                    id: UUID(), name: "NAS", health: .warning, cpu: 42, memory: 81, disk: 88, temperature: 52,
                    updated: .now),
                WidgetSnapshot.Server(id: UUID(), name: "Raspberry Pi", health: .ok, cpu: 7, memory: 31, updated: .now),
            ])
    }
}

extension WidgetSnapshot.Health {
    /// Shapes differ, so the state is readable without color perception.
    var symbolName: String {
        switch self {
        case .unknown, .ok: "server.rack"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .offline: "network.slash"
        }
    }

    var color: Color {
        switch self {
        case .unknown, .offline: .secondary
        case .ok: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .unknown: "Waiting for data"
        case .ok: "OK"
        case .warning: "Warning"
        case .critical: "Critical"
        case .offline: "Offline"
        }
    }
}

private func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "–" }
    return (value / 100).formatted(.percent.precision(.fractionLength(0)))
}

private func level(_ value: Double?) -> Color {
    guard let value else { return .secondary }
    return value >= 90 ? .red : value >= 75 ? .orange : .accentColor
}

/// Shown when MetriBar has not written anything yet.
struct NoDataView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "server.rack").font(.title2)
            Text("Open MetriBar to show your servers.")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .widgetURL(DeepLink.dashboard.url)
    }
}

/// Name and state of a server.
private struct Header: View {
    let server: WidgetSnapshot.Server
    let stale: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: server.health.symbolName).foregroundStyle(server.health.color)
            Text(server.name).font(.headline).lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        if stale {
            Text("Outdated").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct Ring: View {
    let title: LocalizedStringKey
    let value: Double?

    var body: some View {
        VStack(spacing: 3) {
            Gauge(value: min(max((value ?? 0) / 100, 0), 1)) {
                Text(title)
            } currentValueLabel: {
                Text(percent(value)).font(.caption.monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(level(value))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(percent(value)))
    }
}

/// A server that cannot be read: its old values would only mislead.
private struct OfflineBody: View {
    let server: WidgetSnapshot.Server

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Cannot be reached").font(.subheadline.weight(.medium))
            if let updated = server.updated {
                Text("Last data \(updated, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One server: small and medium.
struct ServerStatusView: View {
    let entry: ServerEntry
    let family: WidgetFamily

    var body: some View {
        if let server = entry.server {
            let stale = server.isStale(now: entry.date)
            VStack(alignment: .leading, spacing: 6) {
                Header(server: server, stale: stale && server.health != .offline)
                Spacer(minLength: 0)
                if server.health == .offline {
                    OfflineBody(server: server)
                    Spacer(minLength: 0)
                } else {
                    values(of: server)
                        .opacity(stale ? 0.45 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .widgetURL(DeepLink.server(server.id).url)
        } else {
            NoDataView()
        }
    }

    private func values(of server: WidgetSnapshot.Server) -> some View {
        HStack(alignment: .top, spacing: family == .systemSmall ? 8 : 14) {
            Ring(title: "CPU", value: server.cpu)
            Ring(title: "RAM", value: server.memory)
            if family != .systemSmall {
                Ring(title: "Disk", value: server.disk)
                if let temperature = server.temperature {
                    VStack(spacing: 3) {
                        Text("\(temperature.formatted(.number.precision(.fractionLength(0)))) °C")
                            .font(.caption.monospacedDigit())
                            .frame(height: 38)
                        Text("Temp").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

extension EnvironmentValues {
    /// Whether the rows of the list are links. The snapshot tool turns it
    /// off, because `ImageRenderer` cannot draw a `Link`.
    @Entry var rowsAreLinks = true
}

/// All servers: medium and large.
struct ServerListView: View {
    let entry: ServerEntry
    let family: WidgetFamily

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.servers.isEmpty {
            let rows = Array(snapshot.servers.prefix(family == .systemLarge ? 6 : 3))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { server in
                    RowLink(server: server, entry: entry)
                }
                if snapshot.servers.count > rows.count {
                    Text("+\(snapshot.servers.count - rows.count) more").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        } else {
            NoDataView()
        }
    }

    fileprivate struct Row: View {
        let server: WidgetSnapshot.Server
        let stale: Bool

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: server.health.symbolName)
                    .foregroundStyle(server.health.color)
                    .frame(width: 18)
                Text(server.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: 4)
                Group {
                    Text("CPU \(percent(server.cpu))")
                    Text("RAM \(percent(server.memory))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .opacity(stale ? 0.45 : 1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct RowLink: View {
    let server: WidgetSnapshot.Server
    let entry: ServerEntry
    @Environment(\.rowsAreLinks) private var asLink

    var body: some View {
        let row = ServerListView.Row(server: server, stale: server.isStale(now: entry.date))
        if asLink {
            Link(destination: DeepLink.server(server.id).url) { row }
        } else {
            row
        }
    }
}
