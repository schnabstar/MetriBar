import Foundation

/// Everything MetriBar knows about one server. Each feed fills its own
/// fields; fields of feeds that were never active stay `nil`.
public struct ServerSnapshot: Sendable, Equatable {
    public var status: ServerStatus?
    public var system: SystemInfo?
    /// Plugins the server publishes (`/api/5/pluginslist`).
    public var plugins: Set<String> = []

    public var cpu: Reading<CPU>?
    public var memory: Reading<Memory>?
    public var load: Reading<Load>?
    public var uptime: Uptime?

    public var quickLook: Reading<QuickLook>?
    public var swap: Reading<Swap>?
    public var processCount: ProcessCount?

    public var containers: ItemCollection<ContainerInfo>?
    public var fileSystems: ItemCollection<FileSystem>?
    public var diskIO: ItemCollection<DiskIO>?
    public var network: ItemCollection<NetworkInterface>?
    public var sensors: ItemCollection<Sensor>?
    public var gpus: ItemCollection<GPU>?
    public var processes: [ProcessEntry]?
    public var alerts: [AlertEvent]?
    public var incidents: AlertIncidents?
    public var history = HistorySet()

    /// When each feed was last fetched successfully.
    public var updated: [Feed: Date] = [:]

    public init() {}

    /// Highest threshold level of the values the menu bar watches.
    public var worstLevel: Level {
        [cpu?.worstLevel, memory?.worstLevel, load?.worstLevel, containers?.worstLevel]
            .compactMap { $0 }
            .max() ?? .unknown
    }

    public var hasUnhealthyContainers: Bool {
        containers?.items.contains { $0.isUnhealthy } ?? false
    }
}

public struct HistorySet: Sendable, Equatable {
    public var cpu: History?
    public var memory: History?
    public var load: History?
    public var network: History?

    public init() {}
}

public enum ConnectionState: Sendable, Equatable {
    /// Not started, paused or disabled.
    case idle
    /// First request in progress.
    case connecting
    case connected
    /// The last attempt failed; polling continues with backoff.
    case failed(GlancesError)
    /// The server rejected the credentials. Polling stops until the
    /// credentials change or the user refreshes, so a wrong password cannot
    /// trigger the server's login rate limit.
    case needsCredentials
    /// Not a Glances 5 server. Polling stops.
    case unsupportedVersion(String)
}

/// Summary for the menu bar icon, ordered by severity.
public enum ServerHealth: Int, Sendable, Comparable {
    case unknown
    case ok
    case warning
    case critical
    case offline

    public static func < (lhs: ServerHealth, rhs: ServerHealth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
