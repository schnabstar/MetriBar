import Foundation
import Testing

@testable import MetriBarKit

@MainActor
struct AlertCenterTests {
    let clock = ManualClock()
    let server = FixtureServer()
    private let config = ServerConfig(name: "NAS", url: URL(string: "https://nas.example.com")!)

    private final class Box {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
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
        box.date.addTimeInterval(3600)
        center.handle(.didWake)
        center.evaluate()
        #expect(box.notices.isEmpty)
        box.date.addTimeInterval(120)
        center.evaluate()
        #expect(box.notices.map(\.event) == [.raised])
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
