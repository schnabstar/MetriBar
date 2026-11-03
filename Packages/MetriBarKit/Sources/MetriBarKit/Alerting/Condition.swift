import Foundation

/// One thing about a server that can be fine or a problem: the CPU load,
/// one file system, one temperature sensor. `ServerSnapshot.conditions`
/// lists them, `AlertEvaluator` decides which changes are worth a
/// notification.
public struct Condition: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case cpu, memory, load
        case container
        case sensor
        case fileSystem
        /// The server cannot be read.
        case offline
    }

    public var kind: Kind
    /// Container name, sensor label or mount point; `nil` for the others.
    public var item: String?
    public var level: Level
    /// Percent for CPU, memory and file systems, degrees for sensors, the
    /// five minute average for the load; `nil` if there is none.
    public var value: Double?

    public init(_ kind: Kind, item: String? = nil, level: Level, value: Double? = nil) {
        self.kind = kind
        self.item = item
        self.level = level
        self.value = value
    }
}

extension Condition.Kind {
    /// The feed that delivers the values of this kind; `nil` for `offline`,
    /// which comes from the connection.
    public var feed: Feed? {
        switch self {
        case .cpu, .memory, .load: .core
        case .container: .containers
        case .sensor: .sensors
        case .fileSystem: .storage
        case .offline: nil
        }
    }
}

/// Identifies a condition of one server over time.
public struct ConditionKey: Hashable, Sendable {
    public var serverID: UUID
    public var kind: Condition.Kind
    public var item: String?

    public init(serverID: UUID, kind: Condition.Kind, item: String?) {
        self.serverID = serverID
        self.kind = kind
        self.item = item
    }
}

extension ServerSnapshot {
    /// The values the notifications watch, with their current level.
    ///
    /// CPU, memory, load, containers and temperatures are the sources of
    /// `worstLevel` and thus of the menu bar icon. File systems come in
    /// when the storage feed runs, which it does in the background while
    /// notifications are on; they do not change the icon.
    public var conditions: [Condition] {
        var result: [Condition] = []
        if let cpu {
            result.append(Condition(.cpu, level: cpu.worstLevel, value: cpu.value.total))
        }
        if let memory {
            result.append(Condition(.memory, level: memory.worstLevel, value: memory.value.percent))
        }
        if let load {
            result.append(Condition(.load, level: load.worstLevel, value: load.value.min5))
        }
        for container in containers?.items ?? [] {
            guard let name = container.name else { continue }
            let reported = containers?.levels[name]?.values.map(\.level).max() ?? .unknown
            result.append(
                Condition(.container, item: name, level: container.isUnhealthy ? max(reported, .warning) : reported))
        }
        for sensor in sensors?.items ?? [] where sensor.kind == .temperature {
            guard let label = sensor.label else { continue }
            let reported = sensors?.level("value", item: label) ?? .unknown
            result.append(Condition(.sensor, item: label, level: max(sensor.level, reported), value: sensor.value))
        }
        for fileSystem in fileSystems?.items ?? [] {
            guard let mount = fileSystem.mntPoint else { continue }
            let level = fileSystems?.levels[mount]?.values.map(\.level).max() ?? .unknown
            result.append(Condition(.fileSystem, item: mount, level: level, value: fileSystem.percent))
        }
        return result
    }
}
