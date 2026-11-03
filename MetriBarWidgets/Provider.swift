import AppIntents
import MetriBarKit
import WidgetKit

/// The widgets do not poll: they show what the app wrote, and ask again in
/// a quarter of an hour. The app asks them to reload when something changes.
struct ServerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ServerEntry {
        .placeholder
    }

    func snapshot(for configuration: SelectServerIntent, in context: Context) async -> ServerEntry {
        context.isPreview ? .placeholder : entry(for: configuration)
    }

    func timeline(for configuration: SelectServerIntent, in context: Context) async -> Timeline<ServerEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: SelectServerIntent) -> ServerEntry {
        ServerEntry(date: .now, snapshot: AppGroup.snapshot(), serverID: configuration.server?.id)
    }
}
