import Foundation
import Testing

@testable import MetriBarKit

/// Runs against a real Glances 5 server when `METRIBAR_LIVE_URL` is set, for
/// example `METRIBAR_LIVE_URL=https://glances.example.com swift test`.
/// Optional: `METRIBAR_LIVE_USER` and `METRIBAR_LIVE_PASSWORD`.
@Suite(.enabled(if: LiveServer.url != nil, "Set METRIBAR_LIVE_URL to run"))
struct LiveServerTests {
    private let client = LiveServer.client()

    @Test func serverIsGlances5() async throws {
        let status = try await client.checkServer()
        #expect(status.version == "5")
    }

    @Test func everyEndpointDecodes() async throws {
        let plugins = Set(try await client.get(.pluginsList))
        _ = try await client.get(.system)
        _ = try await client.get(.cpu)
        _ = try await client.get(.perCPU)
        _ = try await client.get(.quickLook)
        _ = try await client.get(.memory)
        _ = try await client.get(.swap)
        _ = try await client.get(.load)
        _ = try await client.get(.uptime)
        _ = try await client.get(.processCount)
        _ = try await client.get(.fileSystems)
        _ = try await client.get(.diskIO)
        _ = try await client.get(.network)
        _ = try await client.get(.topProcesses(10))
        _ = try await client.get(.alerts)
        _ = try await client.get(.incidents)
        _ = try await client.get(.history("cpu", count: 10))
        if plugins.contains("containers") { _ = try await client.get(.containers) }
        if plugins.contains("sensors") { _ = try await client.get(.sensors) }
        if plugins.contains("gpu") { _ = try await client.get(.gpu) }
    }

    @Test func liveValuesAreFilled() async throws {
        let cpu = try await client.get(.cpu)
        #expect(cpu.value.total != nil)
        #expect(cpu.level("total") != .unknown)
        let memory = try await client.get(.memory)
        #expect(memory.value.percent != nil)
        let uptime = try await client.get(.uptime)
        #expect(uptime.value.duration != nil)
    }
}

enum LiveServer {
    static var url: URL? {
        ProcessInfo.processInfo.environment["METRIBAR_LIVE_URL"].flatMap(URL.init(string:))
    }

    static func client() -> GlancesClient {
        let environment = ProcessInfo.processInfo.environment
        let credentials = environment["METRIBAR_LIVE_PASSWORD"].map {
            Credentials(username: environment["METRIBAR_LIVE_USER"] ?? "glances", password: $0)
        }
        return GlancesClient(baseURL: url ?? URL(string: "http://localhost:61208")!, credentials: credentials)
    }
}
