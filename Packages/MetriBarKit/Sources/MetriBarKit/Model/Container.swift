import Foundation

/// One item of `/api/5/containers` (Docker, Podman or LXD).
public struct ContainerInfo: Decodable, Sendable, Equatable {
    @Lenient public var id: String?
    @Lenient public var name: String?
    /// Image tags. Glances 5.0.0b1 sends a list, the documentation a string.
    @Lenient public var image: StringList?
    /// Engine status such as `running` or `exited`. For containers with a
    /// health check Glances reports the health instead, such as `healthy`.
    @Lenient public var status: String?
    @Lenient public var created: String?
    @Lenient public var command: StringList?
    @Lenient public var cpuPercent: Double?
    @Lenient public var cpuLimit: Double?
    /// Bytes.
    @Lenient public var memoryUsage: Double?
    @Lenient public var memoryUsageNoCache: Double?
    @Lenient public var memoryLimit: Double?
    @Lenient public var memoryPercent: Double?
    /// Bytes per second.
    @Lenient public var ioRx: Double?
    @Lenient public var ioWx: Double?
    /// Bits per second.
    @Lenient public var networkRx: Double?
    @Lenient public var networkTx: Double?
    @Lenient public var ports: StringList?
    /// Unix timestamp, `nil` when the container is not running.
    @Lenient public var startedAt: Double?
    @Lenient public var engine: String?
    @Lenient public var podName: String?
    @Lenient public var podId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, image, status, created, command
        case cpuPercent = "cpu_percent"
        case cpuLimit = "cpu_limit"
        case memoryUsage = "memory_usage"
        case memoryUsageNoCache = "memory_usage_no_cache"
        case memoryLimit = "memory_limit"
        case memoryPercent = "memory_percent"
        case ioRx = "io_rx"
        case ioWx = "io_wx"
        case networkRx = "network_rx"
        case networkTx = "network_tx"
        case ports
        case startedAt = "started_at"
        case engine
        case podName = "pod_name"
        case podId = "pod_id"
    }

    public var imageName: String? {
        image?.values.first
    }

    public var startDate: Date? {
        startedAt.map { Date(timeIntervalSince1970: $0) }
    }

    /// Whether the container is up, including the health states Glances
    /// reports in place of `running`.
    public var isRunning: Bool {
        guard let status = status?.lowercased() else { return false }
        return ["running", "healthy", "unhealthy", "starting"].contains(status)
    }

    /// Whether a health check reports a problem.
    public var isUnhealthy: Bool {
        status?.lowercased() == "unhealthy"
    }
}
