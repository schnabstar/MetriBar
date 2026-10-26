/// `GET /status`: served without authentication, used to detect Glances 5.
public struct ServerStatus: Decodable, Sendable, Equatable {
    @Lenient public var status: String?
    /// API version, `"5"` for Glances 5.
    @Lenient public var version: String?
    @Lenient public var glancesVersion: String?

    enum CodingKeys: String, CodingKey {
        case status
        case version
        case glancesVersion = "glances_version"
    }
}

/// `/api/5/system`
public struct SystemInfo: Decodable, Sendable, Equatable {
    @Lenient public var hostname: String?
    /// Human readable OS name, for example "Debian GNU/Linux 13 64bit / Linux 6.18".
    @Lenient public var hrName: String?
    @Lenient public var osName: String?
    @Lenient public var linuxDistro: String?
    @Lenient public var osVersion: String?
    @Lenient public var platform: String?

    enum CodingKeys: String, CodingKey {
        case hostname
        case hrName = "hr_name"
        case osName = "os_name"
        case linuxDistro = "linux_distro"
        case osVersion = "os_version"
        case platform
    }
}

/// `/api/5/uptime`
public struct Uptime: Decodable, Sendable, Equatable {
    @Lenient public var seconds: Double?

    public var duration: Duration? {
        seconds.map { .seconds($0) }
    }
}

/// `/api/5/processcount`
public struct ProcessCount: Decodable, Sendable, Equatable {
    @Lenient public var total: Int?
    @Lenient public var running: Int?
    @Lenient public var sleeping: Int?
    @Lenient public var thread: Int?
}

/// Thresholds from `/api/5/<plugin>/limits`.
public struct Thresholds: Decodable, Sendable, Equatable {
    @Lenient public var careful: Double?
    @Lenient public var warning: Double?
    @Lenient public var critical: Double?
}
