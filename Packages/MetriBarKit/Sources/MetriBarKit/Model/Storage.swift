/// One item of `/api/5/fs`: sizes in bytes.
public struct FileSystem: Decodable, Sendable, Equatable {
    @Lenient public var mntPoint: String?
    @Lenient public var deviceName: String?
    @Lenient public var fsType: String?
    @Lenient public var size: Double?
    @Lenient public var used: Double?
    @Lenient public var free: Double?
    @Lenient public var percent: Double?

    enum CodingKeys: String, CodingKey {
        case mntPoint = "mnt_point"
        case deviceName = "device_name"
        case fsType = "fs_type"
        case size, used, free, percent
    }
}

/// One item of `/api/5/diskio`.
public struct DiskIO: Decodable, Sendable, Equatable {
    @Lenient public var diskName: String?
    /// Bytes per second.
    @Lenient public var readBytes: Double?
    @Lenient public var writeBytes: Double?
    /// Operations per second.
    @Lenient public var readCount: Double?
    @Lenient public var writeCount: Double?
    /// Mean time per operation in milliseconds.
    @Lenient public var readLatency: Double?
    @Lenient public var writeLatency: Double?
    /// Bytes since boot.
    @Lenient public var readBytesCumul: Double?
    @Lenient public var writeBytesCumul: Double?
    @Lenient public var hidden: Bool?

    enum CodingKeys: String, CodingKey {
        case diskName = "disk_name"
        case readBytes = "read_bytes"
        case writeBytes = "write_bytes"
        case readCount = "read_count"
        case writeCount = "write_count"
        case readLatency = "read_latency"
        case writeLatency = "write_latency"
        case readBytesCumul = "read_bytes_cumul"
        case writeBytesCumul = "write_bytes_cumul"
        case hidden
    }
}
