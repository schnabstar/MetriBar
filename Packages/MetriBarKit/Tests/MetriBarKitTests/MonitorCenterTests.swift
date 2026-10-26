import Foundation
import Testing

@testable import MetriBarKit

@MainActor
struct MonitorCenterTests {
    let clock = ManualClock()
    let home = FixtureServer()
    let nas = FixtureServer()

    private let homeConfig = ServerConfig(name: "Home", url: URL(string: "https://home.example.com")!)
    private let nasConfig = ServerConfig(name: "NAS", url: URL(string: "https://nas.example.com")!)

    private func makeCenter() -> MonitorCenter {
        let servers = ["home.example.com": home, "nas.example.com": nas]
        return MonitorCenter(clock: clock) { config in
            let server = servers[config.url.host() ?? ""]!
            return GlancesClient(baseURL: config.url, transport: server.transport)
        }
    }

    @Test func createsMonitorsAndStartsEnabledOnes() async {
        let center = makeCenter()
        var disabled = nasConfig
        disabled.isEnabled = false
        center.apply([homeConfig, disabled])
        defer { center.stopAll() }

        #expect(center.monitors.map(\.config.name) == ["Home", "NAS"])
        await waitUntil { center.monitor(for: homeConfig.id)?.state == .connected }
        #expect(center.monitor(for: nasConfig.id)?.state == .idle)
        #expect(nas.paths.isEmpty)
        // Disabled servers do not count for the menu bar.
        #expect(center.health == center.monitor(for: homeConfig.id)?.health)
    }

    @Test func removesReordersAndUpdatesMonitors() async {
        let center = makeCenter()
        center.apply([homeConfig, nasConfig])
        defer { center.stopAll() }
        let homeMonitor = center.monitor(for: homeConfig.id)
        await waitUntil { homeMonitor?.state == .connected }

        var renamed = nasConfig
        renamed.name = "Storage"
        center.apply([renamed])
        #expect(center.monitors.count == 1)
        #expect(center.monitors.first?.displayName == "Storage")
        #expect(homeMonitor?.state == .idle)  // stopped

        center.apply([homeConfig, renamed])
        center.apply([renamed, homeConfig])
        #expect(center.monitors.map(\.id) == [nasConfig.id, homeConfig.id])
    }

    @Test func healthIsTheWorstOfAllServers() async {
        nas.goOffline()
        let center = makeCenter()
        center.apply([homeConfig, nasConfig])
        defer { center.stopAll() }

        await waitUntil { center.monitor(for: homeConfig.id)?.state == .connected }
        await waitUntil { center.monitor(for: nasConfig.id)?.consecutiveFailures == 1 }
        #expect(center.monitor(for: homeConfig.id)?.health == .ok)
        // A server that never answered counts as offline.
        #expect(center.health == .offline)
    }

    @Test func sleepPausesAndWakeResumes() async {
        let center = makeCenter()
        center.apply([homeConfig])
        defer { center.stopAll() }
        await waitUntil { !clock.pendingDelays.isEmpty }

        center.handle(.willSleep)
        #expect(clock.pendingDelays.isEmpty)
        let requests = home.paths.count
        clock.advance(by: .seconds(3600))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(home.paths.count == requests)

        center.handle(.didWake)
        await waitUntil { home.count("/api/5/cpu") == 2 }
    }

    @Test func reconnectRebuildsTheClient() async {
        let center = makeCenter()
        center.apply([homeConfig])
        defer { center.stopAll() }
        await waitUntil { center.monitor(for: homeConfig.id)?.state == .connected }

        center.reconnect(homeConfig.id)
        await waitUntil { home.count("/status") == 2 }
    }
}
