import Foundation

/// Persists the rules in UserDefaults. Contains nothing secret.
@MainActor
public final class RuleStore {
    private struct Stored: Codable {
        var version = 1
        var rules: [ThresholdRule]
    }

    private struct StoredLossy: Decodable {
        var rules: LossyArray<ThresholdRule>
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "rules") {
        self.defaults = defaults
        self.key = key
    }

    /// Loads the rules. Entries that cannot be decoded, for example a metric
    /// of a later version, are skipped so one broken rule does not lose the rest.
    public func load() -> [ThresholdRule] {
        guard let data = defaults.data(forKey: key),
            let stored = try? JSONDecoder().decode(StoredLossy.self, from: data)
        else { return [] }
        return stored.rules.elements
    }

    public func save(_ rules: [ThresholdRule]) {
        guard let data = try? JSONEncoder().encode(Stored(rules: rules)) else { return }
        defaults.set(data, forKey: key)
    }
}
