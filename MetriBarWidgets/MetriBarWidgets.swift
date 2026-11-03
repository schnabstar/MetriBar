import AppIntents
import MetriBarKit
import SwiftUI
import WidgetKit

@main
struct MetriBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        ServerStatusWidget()
        ServerListWidget()
        StatusControl()
    }
}

struct ServerStatusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKind.server, intent: SelectServerIntent.self, provider: ServerProvider()
        ) {
            entry in
            ServerStatusContainer(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Server")
        .description("CPU, memory, disk and temperature of one server.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ServerListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKind.servers, intent: SelectServerIntent.self, provider: ServerProvider()
        ) {
            entry in
            ServerListContainer(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("All Servers")
        .description("The state of all your servers at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// A control for the Control Center and the menu bar: shows the state of
/// all servers and opens the dashboard.
struct StatusControl: ControlWidget {
    struct Value {
        var health: WidgetSnapshot.Health
        var problems: Int
    }

    struct Provider: ControlValueProvider {
        var previewValue: Value { Value(health: .ok, problems: 0) }

        func currentValue() async throws -> Value {
            let snapshot = AppGroup.snapshot()
            let problems =
                snapshot?.servers.filter { $0.health.severity >= WidgetSnapshot.Health.warning.severity }.count ?? 0
            return Value(health: snapshot?.overallHealth ?? .unknown, problems: problems)
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.status, provider: Provider()) { value in
            ControlWidgetButton(action: OpenURLIntent(DeepLink.dashboard.url)) {
                Label(
                    value.problems > 0 ? "\(value.problems) need attention" : value.health.label,
                    systemImage: value.health.symbolName)
            }
        }
        .displayName("MetriBar")
        .description("The state of your servers. Opens the dashboard.")
    }
}

/// The views take the size as a parameter, so the snapshot tool can render
/// them; the environment's `widgetFamily` cannot be set.
private struct ServerStatusContainer: View {
    let entry: ServerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ServerStatusView(entry: entry, family: family)
    }
}

private struct ServerListContainer: View {
    let entry: ServerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ServerListView(entry: entry, family: family)
    }
}
