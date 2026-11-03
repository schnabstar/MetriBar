import Foundation

/// What a rule measures.
public struct RuleMetric: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case cpu, memory, swap, load, disk, temperature, networkDown, networkUp
    }

    public enum Unit: Sendable {
        case percent
        /// The five minute load average.
        case load
        case celsius
        case megabytesPerSecond
    }

    public var kind: Kind
    /// Mount point for `disk`, sensor label for `temperature`; `nil` for
    /// every one of them. Ignored for the other kinds.
    public var item: String?

    public init(_ kind: Kind, item: String? = nil) {
        self.kind = kind
        self.item = kind.supportsItem ? item : nil
    }
}

extension RuleMetric.Kind {
    public var unit: RuleMetric.Unit {
        switch self {
        case .cpu, .memory, .swap, .disk: .percent
        case .load: .load
        case .temperature: .celsius
        case .networkDown, .networkUp: .megabytesPerSecond
        }
    }

    /// The feed that delivers the value.
    public var feed: Feed {
        switch self {
        case .cpu, .memory, .load: .core
        case .swap, .disk: .storage
        case .temperature: .sensors
        case .networkDown, .networkUp: .network
        }
    }

    public var supportsItem: Bool {
        self == .disk || self == .temperature
    }

    /// How far a value has to move back from the limit before the rule
    /// stops firing, so a value that hovers at the limit does not flip.
    public func hysteresis(limit: Double) -> Double {
        switch unit {
        case .percent: 3
        case .load: 0.2
        case .celsius: 2
        case .megabytesPerSecond: max(abs(limit) * 0.05, 0.1)
        }
    }
}

/// A limit the user set for one value of one server or of all servers,
/// for example "CPU above 90 % for 5 minutes". Rules only change what
/// MetriBar shows and reports; they never change anything on a server.
public struct ThresholdRule: Codable, Sendable, Identifiable, Equatable {
    public enum Comparison: String, Codable, Sendable, CaseIterable {
        case above, below
    }

    public enum Severity: String, Codable, Sendable, CaseIterable {
        case warning, critical

        public var level: Level {
            self == .critical ? .critical : .warning
        }
    }

    public static let holdChoices = [0, 60, 300, 900]

    public var id: UUID
    /// The server the rule is for; `nil` for all.
    public var serverID: UUID?
    public var metric: RuleMetric
    public var comparison: Comparison
    /// In the unit of the metric: percent, load, degrees Celsius or MB/s.
    public var limit: Double
    /// How long the limit has to be exceeded before the rule fires.
    public var holdSeconds: Int
    public var severity: Severity
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(), serverID: UUID? = nil, metric: RuleMetric, comparison: Comparison = .above,
        limit: Double, holdSeconds: Int = 0, severity: Severity = .warning, isEnabled: Bool = true
    ) {
        self.id = id
        self.serverID = serverID
        self.metric = metric
        self.comparison = comparison
        self.limit = limit
        self.holdSeconds = holdSeconds
        self.severity = severity
        self.isEnabled = isEnabled
    }

    public func appliesTo(_ server: UUID) -> Bool {
        isEnabled && (serverID == nil || serverID == server)
    }

    /// The value is on the wrong side of the limit.
    public func isViolated(by value: Double) -> Bool {
        switch comparison {
        case .above: value > limit
        case .below: value < limit
        }
    }

    /// The value is far enough back on the right side to end a firing rule.
    public func isCleared(by value: Double) -> Bool {
        let margin = metric.kind.hysteresis(limit: limit)
        switch comparison {
        case .above: return value <= limit - margin
        case .below: return value >= limit + margin
        }
    }

    /// The feeds the rules need in the background, beyond the usual ones.
    public static func requiredFeeds(_ rules: [ThresholdRule]) -> Set<Feed> {
        Set(rules.filter(\.isEnabled).map { $0.metric.kind.feed }).subtracting(Feed.background)
    }
}

extension ThresholdRule {
    private enum CodingKeys: String, CodingKey {
        case id, serverID, metric, comparison, limit, holdSeconds, severity, isEnabled
    }

    /// Only the metric and the limit are required; the rest falls back to a
    /// default, so a later version can add fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            serverID: try? container.decodeIfPresent(UUID.self, forKey: .serverID),
            metric: try container.decode(RuleMetric.self, forKey: .metric),
            comparison: (try? container.decodeIfPresent(Comparison.self, forKey: .comparison)) ?? .above,
            limit: try container.decode(Double.self, forKey: .limit),
            holdSeconds: min(max((try? container.decodeIfPresent(Int.self, forKey: .holdSeconds)) ?? 0, 0), 86_400),
            severity: (try? container.decodeIfPresent(Severity.self, forKey: .severity)) ?? .warning,
            isEnabled: (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true)
    }
}
