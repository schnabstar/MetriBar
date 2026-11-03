import Foundation
import Testing

@testable import MetriBarKit

@MainActor
struct ServerConfigTests {
    private let id = UUID()
    private let fingerprint = String(repeating: "ab", count: 32)

    /// The format of MetriBar 0.11.0, before `notificationsEnabled`.
    private var legacyJSON: String {
        """
        {"id":"\(id.uuidString)","name":"NAS","url":"https://nas.example.com:61208",
         "username":"glances","isEnabled":false,
         "pinnedCertificate":"\(fingerprint)"}
        """
    }

    @Test func decodesTheFormatOf011() throws {
        let config = try JSONDecoder().decode(ServerConfig.self, from: Data(legacyJSON.utf8))
        #expect(config.id == id)
        #expect(config.name == "NAS")
        #expect(config.url.host() == "nas.example.com")
        #expect(config.username == "glances")
        #expect(!config.isEnabled)
        #expect(config.pinnedCertificate?.bytes.count == 32)
        #expect(config.notificationsEnabled)
    }

    @Test func onlyIDAndURLAreRequired() throws {
        let json = Data(#"{"id":"\#(id.uuidString)","url":"http://pi.local:61208"}"#.utf8)
        let config = try JSONDecoder().decode(ServerConfig.self, from: json)
        #expect(config.name.isEmpty)
        #expect(config.isEnabled)
        #expect(config.username == nil)
        #expect(config.pinnedCertificate == nil)
        #expect(config.notificationsEnabled)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ServerConfig.self, from: Data("{}".utf8)) }
    }

    @Test func roundTripsWithTheNewField() throws {
        var config = ServerConfig(id: id, name: "NAS", url: URL(string: "https://nas.example.com")!)
        config.notificationsEnabled = false
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
        #expect(!decoded.notificationsEnabled)
    }

    @Test func storedServersOf011AreStillLoaded() throws {
        let suite = "ServerConfigTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let stored = #"{"version":1,"servers":[\#(legacyJSON)]}"#
        defaults.set(Data(stored.utf8), forKey: "servers")
        let servers = ConfigStore(defaults: defaults).load()
        #expect(servers.map(\.name) == ["NAS"])
        #expect(servers.first?.notificationsEnabled == true)
    }
}
