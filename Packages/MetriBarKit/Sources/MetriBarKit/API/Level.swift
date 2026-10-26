/// Threshold level that Glances 5 attaches to a field in the `_levels` object
/// of a plugin payload.
public enum Level: String, Sendable, Hashable, CaseIterable {
    /// A value Glances sent that this version of MetriBar does not know.
    case unknown
    case ok
    case careful
    case warning
    case critical

    private var severity: Int {
        switch self {
        case .unknown: 0
        case .ok: 1
        case .careful: 2
        case .warning: 3
        case .critical: 4
        }
    }
}

extension Level: Comparable {
    public static func < (lhs: Level, rhs: Level) -> Bool {
        lhs.severity < rhs.severity
    }
}

extension Level: Decodable {
    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Level(rawValue: rawValue) ?? .unknown
    }
}

/// One entry of a `_levels` object, for example
/// `{"level": "warning", "prominent": true}`.
public struct LevelInfo: Sendable, Hashable, Decodable {
    public let level: Level
    /// Whether Glances highlights this field in its own UI.
    public let prominent: Bool

    public init(level: Level, prominent: Bool) {
        self.level = level
        self.prominent = prominent
    }

    private enum CodingKeys: String, CodingKey {
        case level
        case prominent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decodeIfPresent(Level.self, forKey: .level) ?? .unknown
        prominent = try container.decodeIfPresent(Bool.self, forKey: .prominent) ?? false
    }
}
