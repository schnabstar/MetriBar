import Foundation

/// What the widgets show: a small, secret-free summary of every server.
///
/// The app writes it into the shared App Group container, the widget
/// extension reads it. The extension does not poll: it would need the
/// Keychain and the network, and a widget may only refresh a few dozen
/// times a day. The snapshot has no passwords, no user names, no URLs, no
/// process or container names and no certificate data; the server name is
/// the one the user sees in the menu bar window.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// Raised when the format changes in a way an older reader cannot use.
    public static let currentVersion = 1
    /// A server whose values are older than this is shown as outdated.
    public static let staleAfter: TimeInterval = 15 * 60

    public enum Health: String, Codable, Sendable, CaseIterable {
        case unknown, ok, warning, critical, offline

        public init(_ health: ServerHealth) {
            switch health {
            case .unknown: self = .unknown
            case .ok: self = .ok
            case .warning: self = .warning
            case .critical: self = .critical
            case .offline: self = .offline
            }
        }

        /// A value of a later version reads as `unknown`.
        public init(from decoder: any Decoder) throws {
            let text = try decoder.singleValueContainer().decode(String.self)
            self = Health(rawValue: text) ?? .unknown
        }

        /// The more serious of two states, for a summary of several servers.
        public var severity: Int {
            switch self {
            case .unknown: 0
            case .ok: 1
            case .warning: 2
            case .critical: 3
            case .offline: 4
            }
        }
    }

    public struct Server: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var health: Health
        /// Percent.
        public var cpu: Double?
        /// Percent.
        public var memory: Double?
        /// Percent of the fullest file system.
        public var disk: Double?
        /// Degrees Celsius of the hottest sensor.
        public var temperature: Double?
        /// When MetriBar last read the server successfully.
        public var updated: Date?

        public init(
            id: UUID, name: String, health: Health, cpu: Double? = nil, memory: Double? = nil, disk: Double? = nil,
            temperature: Double? = nil, updated: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.health = health
            self.cpu = cpu
            self.memory = memory
            self.disk = disk
            self.temperature = temperature
            self.updated = updated
        }

        /// The values are old: the app is not running, or the server has
        /// not been readable for a while.
        public func isStale(now: Date) -> Bool {
            guard let updated else { return true }
            return now.timeIntervalSince(updated) > WidgetSnapshot.staleAfter
        }
    }

    public var version: Int
    public var generated: Date
    public var servers: [Server]

    public init(version: Int = WidgetSnapshot.currentVersion, generated: Date, servers: [Server]) {
        self.version = version
        self.generated = generated
        self.servers = servers
    }

    /// The most serious state of all servers.
    public var overallHealth: Health {
        servers.map(\.health).max { $0.severity < $1.severity } ?? .unknown
    }

    public func server(_ id: UUID) -> Server? {
        servers.first { $0.id == id }
    }
}

extension WidgetSnapshot.Server {
    private enum CodingKeys: String, CodingKey {
        case id, name, health, cpu, memory, disk, temperature, updated
    }

    /// Tolerant: only the id is required.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "",
            health: (try? container.decodeIfPresent(WidgetSnapshot.Health.self, forKey: .health)) ?? .unknown,
            cpu: try? container.decodeIfPresent(Double.self, forKey: .cpu),
            memory: try? container.decodeIfPresent(Double.self, forKey: .memory),
            disk: try? container.decodeIfPresent(Double.self, forKey: .disk),
            temperature: try? container.decodeIfPresent(Double.self, forKey: .temperature),
            updated: try? container.decodeIfPresent(Date.self, forKey: .updated))
    }
}

extension WidgetSnapshot {
    /// The summary of the monitors that are turned on, in their order.
    @MainActor
    public static func make(from monitors: [ServerMonitor], now: Date = Date()) -> WidgetSnapshot {
        let servers = monitors.filter { $0.config.isEnabled }.map { monitor in
            let snapshot = monitor.snapshot
            let readable = monitor.health != .offline && monitor.health != .unknown
            func value(_ metric: MenuBarMetric) -> Double? {
                readable ? MenuBarText.value(metric, from: snapshot) : nil
            }
            return Server(
                id: monitor.id, name: monitor.displayName, health: Health(monitor.health), cpu: value(.cpu),
                memory: value(.memory), disk: value(.disk), temperature: value(.temperature),
                updated: monitor.lastSuccess)
        }
        return WidgetSnapshot(generated: now, servers: servers)
    }
}
