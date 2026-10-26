/// One item of `/api/5/processlist/top/<n>`.
///
/// `cmdline` can contain secrets such as tokens passed as arguments. Never
/// log or persist it, and only show it when the user asks for it.
public struct ProcessEntry: Decodable, Sendable, Equatable {
    @Lenient public var pid: Int?
    @Lenient public var name: String?
    @Lenient public var username: String?
    /// Single letter state, for example `R` running or `S` sleeping.
    @Lenient public var status: String?
    @Lenient public var nice: Int?
    @Lenient public var numThreads: Int?
    /// Can exceed 100 % for multi-threaded processes.
    @Lenient public var cpuPercent: Double?
    @Lenient public var memoryPercent: Double?
    @Lenient public var cmdline: [String]?
    @Lenient public var memoryInfo: MemoryInfo?

    public struct MemoryInfo: Decodable, Sendable, Equatable {
        /// Resident set size in bytes.
        @Lenient public var rss: Double?
        /// Virtual memory size in bytes.
        @Lenient public var vms: Double?
    }

    enum CodingKeys: String, CodingKey {
        case pid, name, username, status, nice
        case numThreads = "num_threads"
        case cpuPercent = "cpu_percent"
        case memoryPercent = "memory_percent"
        case cmdline
        case memoryInfo = "memory_info"
    }
}
