/// `/api/5/cpu`: CPU usage in percent.
public struct CPU: Decodable, Sendable, Equatable {
    @Lenient public var total: Double?
    @Lenient public var user: Double?
    @Lenient public var system: Double?
    @Lenient public var iowait: Double?
    @Lenient public var idle: Double?
    @Lenient public var steal: Double?
    @Lenient public var nice: Double?
    @Lenient public var irq: Double?
    @Lenient public var guest: Double?
    /// Context switches per second.
    @Lenient public var ctxSwitches: Double?
    /// Interrupts per second.
    @Lenient public var interrupts: Double?
    @Lenient public var softInterrupts: Double?
    /// Number of logical cores.
    @Lenient public var cpucore: Int?

    enum CodingKeys: String, CodingKey {
        case total, user, system, iowait, idle, steal, nice, irq, guest
        case ctxSwitches = "ctx_switches"
        case interrupts
        case softInterrupts = "soft_interrupts"
        case cpucore
    }
}

/// One item of `/api/5/percpu`.
public struct CoreUsage: Decodable, Sendable, Equatable {
    @Lenient public var cpuNumber: Int?
    @Lenient public var total: Double?
    @Lenient public var user: Double?
    @Lenient public var system: Double?
    @Lenient public var iowait: Double?
    @Lenient public var idle: Double?
    @Lenient public var steal: Double?

    enum CodingKeys: String, CodingKey {
        case cpuNumber = "cpu_number"
        case total, user, system, iowait, idle, steal
    }
}

/// `/api/5/quicklook`: summary bars as shown at the top of the Glances UI.
public struct QuickLook: Decodable, Sendable, Equatable {
    @Lenient public var cpu: Double?
    @Lenient public var mem: Double?
    @Lenient public var swap: Double?
    /// 15 minute load in percent, normalized by the core count.
    @Lenient public var load: Double?
    @Lenient public var cpuName: String?
    @Lenient public var cpuHz: Double?
    @Lenient public var cpuHzCurrent: Double?
    @Lenient public var cpuLogCore: Int?
    @Lenient public var cpuPhysCore: Int?
    @Lenient public var percpu: [Core]?

    public struct Core: Decodable, Sendable, Equatable {
        @Lenient public var cpuNumber: Int?
        @Lenient public var total: Double?
        @Lenient public var level: Level?

        enum CodingKeys: String, CodingKey {
            case cpuNumber = "cpu_number"
            case total, level
        }
    }

    enum CodingKeys: String, CodingKey {
        case cpu, mem, swap, load
        case cpuName = "cpu_name"
        case cpuHz = "cpu_hz"
        case cpuHzCurrent = "cpu_hz_current"
        case cpuLogCore = "cpu_log_core"
        case cpuPhysCore = "cpu_phys_core"
        case percpu
    }
}

/// `/api/5/load`
public struct Load: Decodable, Sendable, Equatable {
    @Lenient public var min1: Double?
    @Lenient public var min5: Double?
    @Lenient public var min15: Double?
    @Lenient public var cpucore: Int?
}
