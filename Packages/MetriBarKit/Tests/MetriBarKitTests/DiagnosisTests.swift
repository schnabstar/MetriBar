import Foundation
import Testing

@testable import MetriBarKit

@MainActor
struct ConfigStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "metribar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func roundTrip() {
        let store = ConfigStore(defaults: makeDefaults())
        #expect(store.load().isEmpty)
        let servers = [
            ServerConfig(name: "Pi", url: URL(string: "http://pi.local:61208")!),
            ServerConfig(url: URL(string: "https://nas.example.com")!, username: "glances"),
        ]
        store.save(servers)
        #expect(store.load() == servers)
    }

    @Test func skipsBrokenEntries() {
        let defaults = makeDefaults()
        let json = #"""
            {"version": 1, "servers": [
                {"id": "6F1C3A3E-4E3B-4C55-9C8A-1D2E3F4A5B6C", "name": "Good", "url": "http://pi.local", "isEnabled": true},
                {"id": "not-a-uuid", "name": "Broken"}
            ]}
            """#
        defaults.set(Data(json.utf8), forKey: "servers")
        #expect(ConfigStore(defaults: defaults).load().map(\.name) == ["Good"])
    }

    @Test func storesNoPasswords() throws {
        let defaults = makeDefaults()
        ConfigStore(defaults: defaults).save([ServerConfig(url: URL(string: "https://nas.local")!, username: "glances")]
        )
        let data = try #require(defaults.data(forKey: "servers"))
        #expect(!String(decoding: data, as: UTF8.self).lowercased().contains("password"))
    }
}

struct ConnectionProblemTests {
    @Test(arguments: [
        (GlancesError.transport(.cannotFindHost), ConnectionProblem.hostNotFound),
        (.transport(.cannotConnectToHost), .connectionRefused),
        (.transport(.timedOut), .timedOut),
        (.transport(.notConnectedToInternet), .offline),
        (.transport(.secureConnectionFailed), .tlsHandshakeFailed),
        (.transport(.serverCertificateUntrusted), .untrustedCertificate),
        (.transport(.serverCertificateHasBadDate), .untrustedCertificate),
        (.transport(.appTransportSecurityRequiresSecureConnection), .insecureConnectionBlocked),
        (.badRequest(detail: "Invalid host header"), .hostRejected),
        (.unauthorized, .unauthorized),
        (.rateLimited(retryAfter: .seconds(30)), .rateLimited(retryAfter: .seconds(30))),
        (.http(status: 502, detail: nil), .serverError(status: 502)),
        (.notGlances, .notGlances),
        (.unsupportedVersion("4"), .glances4),
        (.unsupportedVersion("6.0.0"), .unsupportedVersion("6.0.0")),
        (.decoding("Unexpected type"), .invalidResponse),
    ])
    func mapsErrors(error: GlancesError, expected: ConnectionProblem) {
        #expect(ConnectionProblem(error) == expected)
    }

    @Test func mapsMonitorStates() {
        #expect(ConnectionProblem(ConnectionState.needsCredentials) == .unauthorized)
        #expect(ConnectionProblem(ConnectionState.unsupportedVersion("4")) == .glances4)
        #expect(ConnectionProblem(ConnectionState.failed(.transport(.timedOut))) == .timedOut)
    }
}

struct ConnectionTestTests {
    private func run(_ server: FixtureServer, denied: Bool? = false) async -> ConnectionTestReport {
        await ConnectionTest.run(client: server.client()) { _ in denied }
    }

    @Test func succeedsAgainstGlances5() async {
        let report = await run(FixtureServer())
        #expect(report.succeeded)
        #expect(report.glancesVersion == "5.0.0b1")
        #expect(report.hostname == "glances-host")
        #expect(report.plugins.contains("containers"))
        #expect(report.problem == nil)
    }

    @Test func reportsRejectedCredentials() async {
        let server = FixtureServer()
        server.override("/api/5/pluginslist", with: StubTransport.Reply(status: 401))
        let report = await run(server)
        #expect(report.server == .passed)
        #expect(report.authentication == .failed(.unauthorized))
        #expect(report.data == .skipped)
        #expect(report.problem == .unauthorized)
    }

    @Test func reportsGlances4() async {
        let server = FixtureServer()
        server.override("/status", with: StubTransport.Reply(status: 404))
        server.override("/api/4/status", with: .json(#"{"version": "4.5.8"}"#))
        let report = await run(server)
        #expect(report.server == .failed(.glances4))
        #expect(report.authentication == .skipped)
    }

    @Test func blamesLocalNetworkPermissionWhenMacOSBlocks() async {
        let server = FixtureServer()
        server.goOffline(.timedOut)
        #expect(await run(server, denied: true).server == .failed(.localNetworkDenied))
        #expect(await run(server, denied: false).server == .failed(.timedOut))
        #expect(await run(server, denied: nil).server == .failed(.timedOut))
    }

    @Test func doesNotCheckLocalNetworkForUnrelatedProblems() async {
        let server = FixtureServer()
        server.goOffline(.serverCertificateUntrusted)
        #expect(await run(server, denied: true).server == .failed(.untrustedCertificate))
    }
}

@MainActor
struct DemoServerTests {
    @Test func demoServerServesEveryFeed() async {
        let monitor = ServerMonitor(config: DemoServer.config(), client: DemoServer.client(), clock: ManualClock())
        monitor.start()
        defer { monitor.stop() }
        let view = Task { await monitor.keepActive(Set(Feed.allCases)) }
        defer { view.cancel() }

        await waitUntil { monitor.snapshot.updated.count == Feed.allCases.count }
        #expect(monitor.state == .connected)
        #expect(monitor.feedErrors.isEmpty)
        #expect(monitor.snapshot.processes?.isEmpty == false)
        #expect(monitor.displayName == "Demo")
    }
}
