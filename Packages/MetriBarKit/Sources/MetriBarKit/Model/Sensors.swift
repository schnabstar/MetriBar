/// One item of `/api/5/sensors`.
public struct Sensor: Decodable, Sendable, Equatable {
    @Lenient public var label: String?
    /// Raw sensor type, for example `temperature_core` or `fan_speed`.
    @Lenient public var type: String?
    @Lenient public var unit: String?
    @Lenient public var value: Double?
    /// Hardware thresholds.
    @Lenient public var warning: Double?
    @Lenient public var critical: Double?
    /// Battery charge status.
    @Lenient public var status: String?

    public enum Kind: Sendable {
        case temperature
        case fan
        case battery
        case other
    }

    public var kind: Kind {
        switch type {
        case let type? where type.hasPrefix("temperature"): .temperature
        case "fan_speed": .fan
        case "battery": .battery
        default: .other
        }
    }
}

/// One item of `/api/5/gpu`.
public struct GPU: Decodable, Sendable, Equatable {
    @Lenient public var gpuId: String?
    @Lenient public var name: String?
    /// Processor usage in percent.
    @Lenient public var proc: Double?
    /// Memory usage in percent.
    @Lenient public var mem: Double?
    /// Degrees Celsius.
    @Lenient public var temperature: Double?
    @Lenient public var fanSpeed: Double?

    enum CodingKeys: String, CodingKey {
        case gpuId = "gpu_id"
        case name, proc, mem, temperature
        case fanSpeed = "fan_speed"
    }
}
