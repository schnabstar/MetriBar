import AppIntents
import MetriBarKit

/// A server the user can choose for a widget.
struct ServerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Server"
    static let defaultQuery = ServerQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ServerQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ServerEntity] {
        servers().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ServerEntity] {
        servers()
    }

    func defaultResult() async -> ServerEntity? {
        servers().first
    }

    private func servers() -> [ServerEntity] {
        (AppGroup.snapshot()?.servers ?? []).map { ServerEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectServerIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Server"
    static let description = IntentDescription("The server this widget shows.")

    @Parameter(title: "Server")
    var server: ServerEntity?
}
