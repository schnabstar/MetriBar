import Foundation
import Testing

@testable import MetriBarKit

@MainActor
struct ServerMonitorTests {
    let server = FixtureServer()
    let clock = ManualClock()

    private func makeMonitor() -> ServerMonitor {
        ServerMonitor(
            config: ServerConfig(url: URL(string: "https://glances.example.com")!),
            client: server.client(),
            clock: clock
        )
    }

    /// Waits until the monitor sleeps again and returns the delay.
    @discardableResult
    private func nextSleep(sourceLocation: SourceLocation = #_sourceLocation) async -> Duration? {
        await waitUntil("monitor did not sleep", sourceLocation: sourceLocation) { !clock.pendingDelays.isEmpty }
        return clock.pendingDelays.first
    }

    /// Advances the clock to the next wake-up and waits for the next sleep.
    @discardableResult
    private func tick(sourceLocation: SourceLocation = #_sourceLocation) async -> Duration? {
        guard let delay = clock.pendingDelays.first else {
            Issue.record("monitor is not sleeping", sourceLocation: sourceLocation)
            return nil
        }
        clock.advance(by: delay)
        return await nextSleep(sourceLocation: sourceLocation)
    }

    // MARK: - Polling

    @Test func startsWithHandshakeAndBackgroundFeeds() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }

        #expect(await nextSleep() == .seconds(10))
        #expect(monitor.state == .connected)
        #expect(monitor.snapshot.status?.version == "5")
        #expect(monitor.snapshot.system?.hostname == "glances-host")
        #expect(monitor.snapshot.plugins.contains("containers"))
        #expect(monitor.snapshot.cpu != nil)
        #expect(monitor.snapshot.memory != nil)
        #expect(monitor.snapshot.load != nil)
        #expect(monitor.snapshot.uptime != nil)
        #expect(monitor.snapshot.containers?.items.isEmpty == false)
        #expect(monitor.lastSuccess != nil)
        #expect(monitor.displayName == "glances-host")
        // Feeds no view asked for are not fetched.
        #expect(monitor.snapshot.fileSystems == nil)
        #expect(server.count("/api/5/fs") == 0)
        #expect(server.count("/api/5/processlist/top/50") == 0)
    }

    @Test func pollsAgainAfterBaseIntervalWithoutRepeatingHandshake() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        #expect(await tick() == .seconds(10))
        #expect(await tick() == .seconds(10))
        #expect(server.count("/api/5/cpu") == 3)
        #expect(server.count("/status") == 1)
        #expect(server.count("/api/5/system") == 1)
    }

    @Test func keepActiveFetchesFeedsAtLiveInterval() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        let view = Task { await monitor.keepActive([.storage]) }
        await waitUntil { monitor.snapshot.fileSystems != nil }
        #expect(await nextSleep() == .seconds(2))
        #expect(monitor.snapshot.diskIO != nil)
        #expect(monitor.snapshot.swap != nil)

        // When the view disappears the monitor returns to the base interval
        // and stops fetching the storage feed.
        view.cancel()
        await waitUntil { clock.pendingDelays == [.seconds(10)] }
        let storageRequests = server.count("/api/5/fs")
        await tick()
        #expect(server.count("/api/5/fs") == storageRequests)
    }

    @Test func overlappingSubscriptionsAreCounted() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        let popover = Task { await monitor.keepActive([.core, .containers]) }
        let dashboard = Task { await monitor.keepActive([.core, .network]) }
        await waitUntil { monitor.snapshot.network != nil }
        popover.cancel()
        // The dashboard still needs live data.
        #expect(await nextSleep() == .seconds(2))
        dashboard.cancel()
        await waitUntil { clock.pendingDelays == [.seconds(10)] }
    }

    @Test func historyIsRefreshedAtItsOwnInterval() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        let view = Task { await monitor.keepActive([.history]) }
        defer { view.cancel() }
        await waitUntil { monitor.snapshot.history.cpu != nil }
        await nextSleep()
        #expect(monitor.snapshot.history.memory?.points("percent").isEmpty == false)
        #expect(monitor.snapshot.history.network?.items(for: "bytes_recv").isEmpty == false)

        // Live interval 2 s, history every 30 s: 14 more polls without history.
        for _ in 0..<14 { await tick() }
        #expect(server.count("/api/5/cpu/history") == 1)
        await tick()
        #expect(server.count("/api/5/cpu/history") == 2)
    }

    // MARK: - Failures

    @Test func backoffDoublesUpToTheMaximum() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        server.goOffline()
        #expect(await tick() == .seconds(10))
        #expect(await tick() == .seconds(20))
        #expect(await tick() == .seconds(40))
        #expect(await tick() == .seconds(60))
        #expect(await tick() == .seconds(60))
        #expect(monitor.state == .failed(.transport(.cannotConnectToHost)))
    }

    @Test func valuesTurnStaleAfterThreeFailuresAndRecover() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()
        let healthy = monitor.health

        server.goOffline(.timedOut)
        await tick()
        await tick()
        // Single failures keep the last values and their health.
        #expect(!monitor.isStale)
        #expect(monitor.health == healthy)
        await tick()
        #expect(monitor.isStale)
        #expect(monitor.health == .offline)
        #expect(monitor.snapshot.cpu != nil)  // last values stay visible

        server.reset()
        #expect(await tick() == .seconds(10))
        #expect(monitor.state == .connected)
        #expect(!monitor.isStale)
        #expect(monitor.consecutiveFailures == 0)
    }

    @Test func rejectedCredentialsStopPollingUntilRefresh() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        server.override("/api/5/cpu", with: .json(#"{"detail": "Not authenticated"}"#, status: 401))
        clock.advance(by: .seconds(10))
        await waitUntil { monitor.state == .needsCredentials }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(clock.pendingDelays.isEmpty)
        #expect(monitor.health == .offline)

        // No further login attempts, however much time passes.
        let requests = server.paths.count
        clock.advance(by: .seconds(3600))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(server.paths.count == requests)

        server.reset()
        monitor.refresh()
        await waitUntil { monitor.state == .connected }
        #expect(server.count("/status") == 2)  // handshake repeated
    }

    @Test func rateLimitWaitsForRetryAfter() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        server.override("/api/5/cpu", with: StubTransport.Reply(status: 429, headers: ["Retry-After": "45"]))
        #expect(await tick() == .seconds(45))
        #expect(monitor.state == .failed(.rateLimited(retryAfter: .seconds(45))))
    }

    @Test func unsupportedVersionStopsPolling() async {
        server.override("/status", with: .json(#"{"status": "ok", "version": "6", "glances_version": "6.0.0"}"#))
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }

        await waitUntil { monitor.state == .unsupportedVersion("6.0.0") }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(clock.pendingDelays.isEmpty)
        #expect(server.count("/api/5/cpu") == 0)
    }

    @Test func detectsGlances4() async {
        server.override("/status", with: .json(#"{"detail": "Not Found"}"#, status: 404))
        server.override("/api/4/status", with: .json(#"{"version": "4.5.8"}"#))
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }

        await waitUntil { monitor.state == .unsupportedVersion("4") }
    }

    @Test func failingOptionalFeedKeepsTheConnection() async {
        server.override("/api/5/sensors", with: StubTransport.Reply(status: 500))
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        let view = Task { await monitor.keepActive([.sensors]) }
        defer { view.cancel() }
        await waitUntil { monitor.feedErrors[.sensors] != nil }
        #expect(monitor.feedErrors[.sensors] == .http(status: 500, detail: nil))
        #expect(monitor.state == .connected)
        #expect(monitor.snapshot.cpu != nil)
    }

    @Test func skipsPluginsTheServerDoesNotPublish() async {
        server.override("/api/5/pluginslist", with: .json(#"["cpu", "mem", "load", "uptime", "system"]"#))
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        let view = Task { await monitor.keepActive([.sensors, .history]) }
        defer { view.cancel() }
        await waitUntil { monitor.snapshot.history.cpu != nil }
        #expect(monitor.snapshot.containers == nil)
        #expect(monitor.snapshot.sensors == nil)
        #expect(monitor.snapshot.history.network == nil)
        #expect(server.count("/api/5/containers") == 0)
        #expect(server.count("/api/5/sensors") == 0)
        #expect(server.count("/api/5/network/history") == 0)
    }

    // MARK: - Lifecycle

    @Test func pauseStopsRequestsAndResumePollsImmediately() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        monitor.pause()
        #expect(clock.pendingDelays.isEmpty)
        let requests = server.paths.count
        clock.advance(by: .seconds(600))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(server.paths.count == requests)

        monitor.resume()
        #expect(await nextSleep() == .seconds(10))
        #expect(server.count("/api/5/cpu") == 2)
    }

    @Test func changingTheURLStartsOver() async {
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()

        let other = FixtureServer()
        let config = ServerConfig(id: monitor.id, url: URL(string: "https://other.example.com")!)
        monitor.update(config: config, client: other.client())
        #expect(monitor.snapshot.cpu == nil)
        await waitUntil { monitor.state == .connected }
        #expect(other.count("/status") == 1)
        #expect(monitor.config.url.host() == "other.example.com")
    }

    @Test func disabledServersDoNotPoll() async {
        let monitor = ServerMonitor(
            config: ServerConfig(url: URL(string: "https://glances.example.com")!, isEnabled: false),
            client: server.client(), clock: clock)
        monitor.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(monitor.state == .idle)
        #expect(server.paths.isEmpty)
    }

    // MARK: - Health

    @Test func healthFollowsGlancesLevels() async {
        server.override(
            "/api/5/cpu",
            with: .json(#"{"total": 97.0, "_levels": {"total": {"level": "critical", "prominent": true}}}"#))
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()
        #expect(monitor.health == .critical)

        server.override("/api/5/cpu", with: .json(#"{"total": 80.0, "_levels": {"total": {"level": "warning"}}}"#))
        await tick()
        #expect(monitor.health == .warning)
    }

    @Test func unhealthyContainerIsAWarning() async {
        server.override(
            "/api/5/containers", with: .json(#"{"_key": "name", "data": [{"name": "db", "status": "unhealthy"}]}"#))
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        await nextSleep()
        #expect(monitor.snapshot.hasUnhealthyContainers)
        #expect(monitor.health == .warning)
    }
}
