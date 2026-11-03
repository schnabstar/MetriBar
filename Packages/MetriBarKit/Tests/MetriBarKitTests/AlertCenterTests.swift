import Foundation
import Testing

@testable import MetriBarKit

@MainActor
struct AlertCenterTests {
    let clock = ManualClock()
    let server = FixtureServer()
    private let config = ServerConfig(name: "NAS", url: URL(string: "https://nas.example.com")!)

    private final class Box {
        // The monitors stamp their feeds with the real time, so start there.
        var date = Date()
        var notices: [AlertNotice] = []
    }

    private func settings(hold: Int = 0) -> NotificationSettings {
        var settings = NotificationSettings()
        settings.isEnabled = true
        settings.holdSeconds = hold
        return settings
    }

    private func makeMonitor(_ config: ServerConfig? = nil) async -> ServerMonitor {
        let config = config ?? self.config
        let monitor = ServerMonitor(config: config, client: server.client(), clock: clock)
        monitor.start()
        await waitUntil("monitor connected") { monitor.state == .connected }
        return monitor
    }

    private func makeCenter(_ monitors: [ServerMonitor], box: Box, hold: Int = 0) -> AlertCenter {
        AlertCenter(
            settings: settings(hold: hold), clock: clock, now: { box.date }, monitors: { monitors },
            deliver: { box.notices += $0 })
    }

    @Test func deliversNoticesForProblemsOfConnectedServers() async {
        server.override(
            "/api/5/cpu", with: .json(#"{"total": 97, "_levels": {"total": {"level": "critical", "prominent": true}}}"#)
        )
        let monitor = await makeMonitor()
        defer { monitor.stop() }
        let box = Box()
        let center = makeCenter([monitor], box: box)

        center.evaluate()
        #expect(box.notices.map(\.event) == [.raised])
        #expect(box.notices.first?.condition.kind == .cpu)
        #expect(box.notices.first?.condition.level == .critical)
        #expect(box.notices.first?.serverName == "NAS")

        // Nothing new the second time.
        center.evaluate()
        #expect(box.notices.count == 1)
    }

    @Test func respectsTheHoldTimeWithTheClockOfTheCaller() async {
        server.override(
            "/api/5/cpu", with: .json(#"{"total": 97, "_levels": {"total": {"level": "warning", "prominent": true}}}"#))
        let monitor = await makeMonitor()
        defer { monitor.stop() }
        let box = Box()
        let center = makeCenter([monitor], box: box, hold: 120)

        center.evaluate()
        box.date.addTimeInterval(60)
        center.evaluate()
        #expect(box.notices.isEmpty)
        box.date.addTimeInterval(60)
        center.evaluate()
        #expect(box.notices.map(\.event) == [.raised])
    }

    @Test func healthyServersAreQuiet() async {
        let monitor = await makeMonitor()
        defer { monitor.stop() }
        let box = Box()
        makeCenter([monitor], box: box).evaluate()
        #expect(box.notices.isEmpty)
    }

    @Test func skipsServersThatAreMutedOrDisabled() async {
        server.override(
            "/api/5/cpu", with: .json(#"{"total": 97, "_levels": {"total": {"level": "critical", "prominent": true}}}"#)
        )
        var muted = config
        muted.notificationsEnabled = false
        let monitor = await makeMonitor(muted)
        defer { monitor.stop() }
        let box = Box()
        makeCenter([monitor], box: box).evaluate()
        #expect(box.notices.isEmpty)
    }

    @Test func reportsAServerThatCannotBeReached() async {
        server.goOffline()
        let monitor = ServerMonitor(config: config, client: server.client(), clock: clock)
        monitor.start()
        defer { monitor.stop() }
        await waitUntil("monitor offline") { monitor.health == .offline }
        let box = Box()
        let center = makeCenter([monitor], box: box)

        center.evaluate()
        #expect(box.notices.map(\.event) == [.offline])
        #expect(box.notices.first?.condition.kind == .offline)

        // Back again: the monitor polls after the next delay.
        server.reset()
        await waitUntil("monitor waits for the next attempt") { !clock.pendingDelays.isEmpty }
        clock.advance(by: clock.pendingDelays.first ?? .seconds(10))
        await waitUntil("monitor back") { monitor.health != .offline }
        box.date.addTimeInterval(30)
        center.evaluate()
        #expect(box.notices.map(\.event) == [.offline, .backOnline])
    }

    @Test func ignoresServersThatAreStillConnecting() {
        let monitor = ServerMonitor(config: config, client: server.client(), clock: clock)
        let box = Box()
        makeCenter([monitor], box: box).evaluate()
        #expect(monitor.health == .unknown)
        #expect(box.notices.isEmpty)
    }

    @Test func wakingResetsWhatWasWaiting() async {
        server.override(
            "/api/5/cpu", with: .json(#"{"total": 97, "_levels": {"total": {"level": "critical", "prominent": true}}}"#)
        )
        let monitor = await makeMonitor()
        defer { monitor.stop() }
        let box = Box()
        let center = makeCenter([monitor], box: box, hold: 120)

        center.evaluate()
        box.date.addTimeInterval(130)
        center.handle(.didWake)
        // Without the reset the start of 130 s ago would report it at once.
        center.evaluate()
        #expect(box.notices.isEmpty)
        box.date.addTimeInterval(120)
        center.evaluate()
        #expect(box.notices.map(\.event) == [.raised])
    }

    // MARK: - Outdated values

    private static let criticalFileSystems = """
        {"_key": "mnt_point", "data": [{"mnt_point": "/mnt/data", "percent": 97}],
         "_levels": {"/mnt/data": {"percent": {"level": "critical", "prominent": true}}}}
        """

    @Test func valuesOfAFailedFeedAreNotReported() async {
        server.override("/api/5/fs", with: .json(Self.criticalFileSystems))
        let monitor = ServerMonitor(config: config, client: server.client(), clock: clock)
        monitor.setExtraBackgroundFeeds([.storage])
        monitor.start()
        defer { monitor.stop() }
        await waitUntil("storage fetched") { monitor.snapshot.fileSystems != nil }
        let box = Box()
        let center = makeCenter([monitor], box: box, hold: 60)

        center.evaluate()
        #expect(box.notices.isEmpty)

        // The file systems fail while the core feed keeps working.
        server.override("/api/5/fs", with: .json(#"{"detail": "broken"}"#, status: 500))
        await waitUntil("monitor waits") { !clock.pendingDelays.isEmpty }
        clock.advance(by: clock.pendingDelays.first ?? .seconds(10))
        await waitUntil("storage failed") { monitor.feedErrors[.storage] != nil }
        #expect(monitor.health != .offline)
        #expect(monitor.snapshot.fileSystems != nil)

        // The old value would be past the hold time by now. It is not looked at.
        // (The monitor stamps its feeds with the real time, so the simulated
        // time stays below the five minutes after which values count as old.)
        box.date.addTimeInterval(70)
        center.evaluate()
        box.date.addTimeInterval(70)
        center.evaluate()
        #expect(box.notices.isEmpty)

        // Fresh values again: the clock for the hold time starts anew.
        server.override("/api/5/fs", with: .json(Self.criticalFileSystems))
        await waitUntil("monitor waits again") { !clock.pendingDelays.isEmpty }
        clock.advance(by: clock.pendingDelays.first ?? .seconds(10))
        await waitUntil("storage back") { monitor.feedErrors[.storage] == nil }
        center.evaluate()
        #expect(box.notices.isEmpty)
        box.date.addTimeInterval(60)
        center.evaluate()
        #expect(box.notices.map(\.event) == [.raised])
        #expect(box.notices.first?.condition.kind == .fileSystem)
    }

    @Test func aFailedFeedDoesNotSilenceTheOthers() async {
        server.override(
            "/api/5/cpu", with: .json(#"{"total": 97, "_levels": {"total": {"level": "critical", "prominent": true}}}"#)
        )
        server.override("/api/5/containers", with: .json(#"{"detail": "broken"}"#, status: 500))
        let monitor = await makeMonitor()
        defer { monitor.stop() }
        await waitUntil("containers failed") { monitor.feedErrors[.containers] != nil }
        let box = Box()
        makeCenter([monitor], box: box).evaluate()
        #expect(box.notices.map(\.condition.kind) == [.cpu])
    }

    @Test func valuesNotFetchedForALongTimeAreNotReported() async {
        server.override(
            "/api/5/cpu", with: .json(#"{"total": 97, "_levels": {"total": {"level": "critical", "prominent": true}}}"#)
        )
        let monitor = await makeMonitor()
        defer { monitor.stop() }
        let box = Box()
        let center = makeCenter([monitor], box: box)

        let fresh = monitor.watchedConditions(now: box.date)
        #expect(fresh.unavailable == [.fileSystem])
        #expect(fresh.conditions.contains { $0.kind == .cpu })

        // The monitor has not polled for ten minutes, for whatever reason.
        box.date.addTimeInterval(600)
        let old = monitor.watchedConditions(now: box.date)
        #expect(old.conditions.isEmpty)
        #expect(old.unavailable.isSuperset(of: [.cpu, .memory, .load, .container, .sensor, .fileSystem]))
        center.evaluate()
        #expect(box.notices.isEmpty)
    }

    @Test func runsEveryFewSecondsWhileOnAndStopsWhenOff() async {
        server.override(
            "/api/5/cpu", with: .json(#"{"total": 97, "_levels": {"total": {"level": "critical", "prominent": true}}}"#)
        )
        let monitor = await makeMonitor()
        defer { monitor.stop() }
        let box = Box()
        let alerts = AlertCenter(
            settings: NotificationSettings(), clock: clock, now: { box.date }, monitors: { [monitor] },
            deliver: { box.notices += $0 })

        // Off by default: no loop.
        alerts.start()
        #expect(!alerts.isRunning)

        alerts.update(settings: settings())
        #expect(alerts.isRunning)
        await waitUntil("first look") { !box.notices.isEmpty }
        #expect(box.notices.count == 1)
        await waitUntil("loop sleeps") { clock.pendingDelays.contains(AlertCenter.interval) }

        alerts.update(settings: NotificationSettings())
        #expect(!alerts.isRunning)
    }
}
