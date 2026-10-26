import Foundation

/// Persists the server list in UserDefaults. Contains no passwords.
@MainActor
public final class ConfigStore {
    private struct Stored: Codable {
        var version = 1
        var servers: [ServerConfig]
    }

    private struct StoredLossy: Decodable {
        var servers: LossyArray<ServerConfig>
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "servers") {
        self.defaults = defaults
        self.key = key
    }

    /// Loads the servers. Entries that cannot be decoded are skipped so a
    /// single broken entry does not lose the whole list.
    public func load() -> [ServerConfig] {
        guard let data = defaults.data(forKey: key),
            let stored = try? JSONDecoder().decode(StoredLossy.self, from: data)
        else { return [] }
        return stored.servers.elements
    }

    public func save(_ servers: [ServerConfig]) {
        guard let data = try? JSONEncoder().encode(Stored(servers: servers)) else { return }
        defaults.set(data, forKey: key)
    }
}
