/// `/api/5/mem`: sizes in bytes.
public struct Memory: Decodable, Sendable, Equatable {
    @Lenient public var total: Double?
    @Lenient public var available: Double?
    @Lenient public var used: Double?
    @Lenient public var free: Double?
    @Lenient public var percent: Double?
    @Lenient public var active: Double?
    @Lenient public var inactive: Double?
    @Lenient public var buffers: Double?
    @Lenient public var cached: Double?
    @Lenient public var shared: Double?
}

/// `/api/5/memswap`: sizes in bytes, `sin` and `sout` in bytes per second.
public struct Swap: Decodable, Sendable, Equatable {
    @Lenient public var total: Double?
    @Lenient public var used: Double?
    @Lenient public var free: Double?
    @Lenient public var percent: Double?
    @Lenient public var sin: Double?
    @Lenient public var sout: Double?
}
