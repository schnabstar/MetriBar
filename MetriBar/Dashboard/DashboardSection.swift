import MetriBarKit

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview, history, storage, network, processes, containers, alerts

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .history: String(localized: "History")
        case .storage: String(localized: "Storage")
        case .network: String(localized: "Network & Sensors")
        case .processes: String(localized: "Processes")
        case .containers: String(localized: "Containers")
        case .alerts: String(localized: "Alerts")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .history: "chart.xyaxis.line"
        case .storage: "internaldrive"
        case .network: "network"
        case .processes: "list.bullet.rectangle"
        case .containers: "shippingbox"
        case .alerts: "bell"
        }
    }

    /// Feeds the section needs while it is visible.
    var feeds: Set<Feed> {
        switch self {
        case .overview: [.core, .overview, .containers, .alerts, .sensors, .storage, .network, .history]
        case .history: [.core, .history]
        case .storage: [.core, .storage]
        case .network: [.core, .network, .sensors]
        case .processes: [.core, .processes]
        case .containers: [.core, .containers]
        case .alerts: [.core, .alerts]
        }
    }

    /// ⌘1 … ⌘7
    var shortcut: Character {
        Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1))
    }
}
