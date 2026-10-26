private enum EnvelopeKeys: String, CodingKey {
    case key = "_key"
    case levels = "_levels"
    case data
}

/// Payload of a plugin with a single set of fields, such as `/api/5/cpu`:
/// the fields plus the `_levels` Glances computes from its thresholds.
public struct Reading<Value: Decodable & Sendable>: Decodable, Sendable {
    public var value: Value
    /// Threshold level per field name.
    public var levels: [String: LevelInfo]

    public init(value: Value, levels: [String: LevelInfo] = [:]) {
        self.value = value
        self.levels = levels
    }

    public init(from decoder: any Decoder) throws {
        value = try Value(from: decoder)
        let container = try decoder.container(keyedBy: EnvelopeKeys.self)
        levels = (try? container.decodeIfPresent([String: LevelInfo].self, forKey: .levels)) ?? [:]
    }

    public func level(_ field: String) -> Level {
        levels[field]?.level ?? .unknown
    }

    /// The highest level of all fields.
    public var worstLevel: Level {
        levels.values.map(\.level).max() ?? .unknown
    }
}

extension Reading: Equatable where Value: Equatable {}

/// Payload of a plugin with a list of items, such as `/api/5/containers`.
public struct ItemCollection<Item: Decodable & Sendable>: Decodable, Sendable {
    public var items: [Item]
    /// Name of the field that identifies an item (`_key`), for example
    /// `name` for containers or `mnt_point` for file systems.
    public var key: String?
    /// Threshold level per item key and field name.
    public var levels: [String: [String: LevelInfo]]

    public init(items: [Item], key: String? = nil, levels: [String: [String: LevelInfo]] = [:]) {
        self.items = items
        self.key = key
        self.levels = levels
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: EnvelopeKeys.self)
        items = try container.decodeIfPresent(LossyArray<Item>.self, forKey: .data)?.elements ?? []
        key = try? container.decodeIfPresent(String.self, forKey: .key)
        levels = (try? container.decodeIfPresent([String: [String: LevelInfo]].self, forKey: .levels)) ?? [:]
    }

    public func level(_ field: String, item itemKey: String) -> Level {
        levels[itemKey]?[field]?.level ?? .unknown
    }

    /// The highest level of all fields of all items.
    public var worstLevel: Level {
        levels.values.flatMap(\.values).map(\.level).max() ?? .unknown
    }
}

extension ItemCollection: Equatable where Item: Equatable {}
