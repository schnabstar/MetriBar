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

    @Test func notificationSettingOfAServerDoesNotRestartItsMonitor() async {
        let center = makeCenter()
        center.apply([homeConfig])
        defer { center.stopAll() }
        await waitUntil { center.monitor(for: homeConfig.id)?.state == .connected }
        let requests = home.paths.count

        var muted = homeConfig
        muted.notificationsEnabled = false
        center.apply([muted])
        let monitor = center.monitor(for: homeConfig.id)
        #expect(monitor?.config.notificationsEnabled == false)
        #expect(monitor?.state == .connected)
        #expect(home.paths.count == requests)

        // Other changes still reconnect.
        var renamedURL = muted
        renamedURL.username = "glances"
        center.apply([renamedURL])
        #expect(center.monitor(for: homeConfig.id)?.state == .connecting)
    }

    @Test func extraBackgroundFeedsReachExistingAndNewMonitors() async {
        let center = makeCenter()
        center.apply([homeConfig])
        defer { center.stopAll() }
        await waitUntil { center.monitor(for: homeConfig.id)?.state == .connected }
        #expect(home.count("/api/5/fs") == 0)

        center.setExtraBackgroundFeeds([.storage])
        await waitUntil("storage fetched") { center.monitor(for: homeConfig.id)?.snapshot.fileSystems != nil }
        #expect(home.count("/api/5/fs") >= 1)

        center.apply([homeConfig, nasConfig])
        await waitUntil("storage fetched for the new server") {
            center.monitor(for: nasConfig.id)?.snapshot.fileSystems != nil
        }

        // Back to the usual set: the file systems are not fetched any more.
        center.setExtraBackgroundFeeds([])
        #expect(center.extraBackgroundFeeds.isEmpty)
    }
}
