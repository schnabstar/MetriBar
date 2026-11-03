import Foundation
import Testing

@testable import MetriBarKit

@MainActor
struct RuleIntegrationTests {
    let clock = ManualClock()
    let server = FixtureServer()
    private let config = ServerConfig(name: "NAS", url: URL(string: "https://nas.example.com")!)

    private static let cpu50 = StubTransport.Reply.json(#"{"total": 50}"#)

    private func makeMonitor(rules: [ThresholdRule] = [], extra: Set<Feed> = []) async -> ServerMonitor {
        server.override("/api/5/cpu", with: Self.cpu50)
        let monitor = ServerMonitor(config: config, client: server.client(), clock: clock)
        monitor.setExtraBackgroundFeeds(extra)
        monitor.setRules(rules)
        monitor.start()
        await waitUntil("monitor connected") { monitor.state == .connected }
        return monitor
    }

    // MARK: - Health

    @Test func aFiringRuleChangesTheHealthOfTheServer() async {
        let monitor = await makeMonitor()
        defer { monitor.stop() }
        #expect(monitor.health == .ok)

        monitor.setRules([ThresholdRule(metric: RuleMetric(.cpu), limit: 10)])
        #expect(monitor.ruleConditions.map(\.level) == [.warning])
        #expect(monitor.health == .warning)

        monitor.setRules([ThresholdRule(metric: RuleMetric(.cpu), limit: 10, severity: .critical)])
        #expect(monitor.health == .critical)

        monitor.setRules([ThresholdRule(metric: RuleMetric(.cpu), limit: 80, severity: .critical)])
        #expect(monitor.ruleConditions.map(\.level) == [.ok])
        #expect(monitor.health == .ok)

        monitor.setRules([])
        #expect(monitor.ruleConditions.isEmpty)
    }

    @Test func rulesApplyFromTheStartAndFromEachPoll() async {
        let rules = [ThresholdRule(metric: RuleMetric(.cpu), limit: 10)]
        let monitor = await makeMonitor(rules: rules)
        defer { monitor.stop() }
        #expect(monitor.health == .warning)

        // The value drops under the hysteresis with the next poll.
        server.override("/api/5/cpu", with: .json(#"{"total": 2}"#))
        await waitUntil("monitor waits") { !clock.pendingDelays.isEmpty }
        clock.advance(by: clock.pendingDelays.first ?? .seconds(10))
        await waitUntil("rule ended") { monitor.health == .ok }
    }

    @Test func onlyTheRulesOfThisServerCount() async {
        let other = ThresholdRule(serverID: UUID(), metric: RuleMetric(.cpu), limit: 10)
        let monitor = await makeMonitor(rules: [other])
        defer { monitor.stop() }
        #expect(monitor.ruleConditions.isEmpty)
        #expect(monitor.health == .ok)

        let mine = ThresholdRule(serverID: config.id, metric: RuleMetric(.cpu), limit: 10)
        monitor.setRules([other, mine])
        #expect(monitor.health == .warning)
    }

    @Test func aRuleOnAnotherFeedWaitsForItsData() async {
        let rule = ThresholdRule(metric: RuleMetric(.disk), limit: 10)
        // Without the storage feed in the background there is no data.
        let without = await makeMonitor(rules: [rule])
        #expect(without.ruleConditions.isEmpty)
        without.stop()

        let monitor = await makeMonitor(rules: [rule], extra: ThresholdRule.requiredFeeds([rule]))
        defer { monitor.stop() }
        await waitUntil("storage fetched") { monitor.snapshot.fileSystems != nil }
        // The fixture has file systems at 20 % and 5.7 %.
        #expect(monitor.ruleConditions.contains { $0.level == .warning && $0.rule?.itemName == "/mnt/volume-01" })
        #expect(monitor.ruleConditions.contains { $0.level == .ok && $0.rule?.itemName == "/mnt/volume-02" })
        #expect(monitor.health == .warning)
    }

    @Test func aFailedFeedKeepsTheStateOfItsRules() async {
        let rule = ThresholdRule(metric: RuleMetric(.disk, item: "/mnt/volume-01"), limit: 10)
        let monitor = await makeMonitor(rules: [rule], extra: [.storage])
        defer { monitor.stop() }
        await waitUntil("storage fetched") { monitor.ruleConditions.contains { $0.level == .warning } }

        server.override("/api/5/fs", with: .json(#"{"detail": "broken"}"#, status: 500))
        await waitUntil("monitor waits") { !clock.pendingDelays.isEmpty }
        clock.advance(by: clock.pendingDelays.first ?? .seconds(10))
        await waitUntil("storage failed") { monitor.feedErrors[.storage] != nil }
        #expect(monitor.ruleConditions.map(\.level) == [.warning])
    }

    // MARK: - Interrupted observation

    private final class Clockwork {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func makeTimedMonitor(_ rule: ThresholdRule, _ time: Clockwork) async -> ServerMonitor {
        server.override("/api/5/cpu", with: .json(#"{"total": 95}"#))
        let monitor = ServerMonitor(config: config, client: server.client(), clock: clock, now: { time.date })
        monitor.setRules([rule])
        monitor.start()
        await waitUntil("monitor connected") { monitor.state == .connected }
        return monitor
    }

    private func poll(_ monitor: ServerMonitor, until condition: () -> Bool) async {
        await waitUntil("monitor waits") { !clock.pendingDelays.isEmpty }
        clock.advance(by: clock.pendingDelays.first ?? .seconds(10))
        await waitUntil("poll finished", condition)
    }

    @Test func anOutageDoesNotCountTowardsTheHoldTime() async {
        let time = Clockwork()
        let rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 90, holdSeconds: 300)
        let monitor = await makeTimedMonitor(rule, time)
        defer { monitor.stop() }
        #expect(monitor.ruleConditions.map(\.level) == [.ok])

        // The connection fails; ten minutes pass before it is back.
        server.goOffline()
        await poll(monitor) { monitor.consecutiveFailures > 0 }
        time.date.addTimeInterval(600)
        server.reset()
        server.override("/api/5/cpu", with: .json(#"{"total": 95}"#))
        await poll(monitor) { monitor.consecutiveFailures == 0 }
        // Without the reset the start from before the outage would fire it now.
        #expect(monitor.ruleConditions.map(\.level) == [.ok])

        time.date.addTimeInterval(299)
        await poll(monitor) { monitor.snapshot.updated[.core] == time.date }
        #expect(monitor.ruleConditions.map(\.level) == [.ok])
        time.date.addTimeInterval(1)
        await poll(monitor) { monitor.snapshot.updated[.core] == time.date }
        #expect(monitor.ruleConditions.map(\.level) == [.warning])
    }

    @Test func sleepingDoesNotCountTowardsTheHoldTime() async {
        let time = Clockwork()
        let rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 90, holdSeconds: 300)
        let monitor = await makeTimedMonitor(rule, time)
        defer { monitor.stop() }

        monitor.pause()
        time.date.addTimeInterval(3600)
        monitor.resume()
        await waitUntil("polled after waking") { monitor.snapshot.updated[.core] == time.date }
        #expect(monitor.ruleConditions.map(\.level) == [.ok])
    }

    @Test func aFiringRuleKeepsFiringThroughAnOutage() async {
        let time = Clockwork()
        let rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 90)
        let monitor = await makeTimedMonitor(rule, time)
        defer { monitor.stop() }
        #expect(monitor.ruleConditions.map(\.level) == [.warning])

        server.goOffline()
        await poll(monitor) { monitor.consecutiveFailures > 0 }
        #expect(monitor.ruleConditions.map(\.level) == [.warning])
    }

    // MARK: - Center

    @Test func theCenterHandsRulesToNewAndExistingMonitors() async {
        let center = MonitorCenter(clock: clock) { [server] config in
            GlancesClient(baseURL: config.url, transport: server.transport)
        }
        server.override("/api/5/cpu", with: Self.cpu50)
        let rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 10)
        center.setRules([rule])
        center.apply([config])
        defer { center.stopAll() }
        let monitor = center.monitor(for: config.id)
        await waitUntil("connected") { monitor?.state == .connected }
        #expect(monitor?.health == .warning)

        center.setRules([])
        #expect(monitor?.health == .ok)
        center.setRules([rule])
        #expect(monitor?.health == .warning)
        #expect(center.health == .warning)
    }

    // MARK: - Notifications

    private final class Box {
        var date = Date()
        var notices: [AlertNotice] = []
    }

    private func settings(threshold: NotificationSettings.Threshold = .critical, hold: Int = 600)
        -> NotificationSettings
    {
        var settings = NotificationSettings()
        settings.isEnabled = true
        settings.threshold = threshold
        settings.holdSeconds = hold
        return settings
    }

    @Test func aFiringRuleIsReportedAtOnceWhateverTheGlobalSettingsAre() async {
        // Global settings: only critical, after ten minutes. The rule is a warning without hold time.
        let rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 10)
        let monitor = await makeMonitor(rules: [rule])
        defer { monitor.stop() }
        let box = Box()
        let alerts = AlertCenter(
            settings: settings(), clock: clock, now: { box.date }, monitors: { [monitor] },
            deliver: { box.notices += $0 })

        alerts.evaluate()
        #expect(box.notices.map(\.event) == [.raised])
        let notice = box.notices.first
        #expect(notice?.condition.kind == .rule)
        #expect(notice?.condition.level == .warning)
        #expect(notice?.condition.value == 50)
        #expect(notice?.condition.rule?.limit == 10)
    }

    @Test func aRuleWithAHoldTimeIsReportedWhenItFires() async {
        // The monitor applies the hold time with the real time; a hold of zero
        // here, the hold logic itself is tested with RuleEvaluator.
        let monitor = await makeMonitor(rules: [ThresholdRule(metric: RuleMetric(.cpu), limit: 90)])
        defer { monitor.stop() }
        let box = Box()
        let alerts = AlertCenter(
            settings: settings(threshold: .warning, hold: 0), clock: clock, now: { box.date },
            monitors: { [monitor] }, deliver: { box.notices += $0 })
        alerts.evaluate()
        #expect(box.notices.isEmpty)

        monitor.setRules([ThresholdRule(metric: RuleMetric(.cpu), limit: 40)])
        alerts.evaluate()
        #expect(box.notices.map(\.condition.kind) == [.rule])
    }

    @Test func rulesNeverNotifyWhenNotificationsAreOffForTheServer() async {
        var muted = config
        muted.notificationsEnabled = false
        server.override("/api/5/cpu", with: Self.cpu50)
        let monitor = ServerMonitor(config: muted, client: server.client(), clock: clock)
        monitor.setRules([ThresholdRule(metric: RuleMetric(.cpu), limit: 10)])
        monitor.start()
        defer { monitor.stop() }
        await waitUntil("connected") { monitor.state == .connected }
        let box = Box()
        let alerts = AlertCenter(
            settings: settings(), clock: clock, now: { box.date }, monitors: { [monitor] },
            deliver: { box.notices += $0 })
        alerts.evaluate()
        #expect(box.notices.isEmpty)
        // The icon still shows the rule.
        #expect(monitor.health == .warning)
    }

    @Test func aRuleThatEndsIsReportedAsRecoveredWhenAskedFor() async {
        let monitor = await makeMonitor(rules: [ThresholdRule(metric: RuleMetric(.cpu), limit: 10)])
        defer { monitor.stop() }
        let box = Box()
        var asked = settings()
        asked.notifiesRecovery = true
        let alerts = AlertCenter(
            settings: asked, clock: clock, now: { box.date }, monitors: { [monitor] },
            deliver: { box.notices += $0 })
        alerts.evaluate()
        #expect(box.notices.map(\.event) == [.raised])

        // The value drops under the limit and its hysteresis with the next poll.
        server.override("/api/5/cpu", with: .json(#"{"total": 2}"#))
        await waitUntil("monitor waits") { !clock.pendingDelays.isEmpty }
        clock.advance(by: clock.pendingDelays.first ?? .seconds(10))
        await waitUntil("rule ended") { monitor.ruleConditions.map(\.level) == [.ok] }
        box.date.addTimeInterval(30)
        alerts.evaluate()
        #expect(box.notices.map(\.event) == [.raised, .recovered])
        #expect(box.notices.last?.condition.rule?.metric == RuleMetric(.cpu))
    }

    @Test func deletingAFiringRuleIsNoRecovery() async {
        let monitor = await makeMonitor(rules: [ThresholdRule(metric: RuleMetric(.cpu), limit: 10)])
        defer { monitor.stop() }
        let box = Box()
        var asked = settings()
        asked.notifiesRecovery = true
        let alerts = AlertCenter(
            settings: asked, clock: clock, now: { box.date }, monitors: { [monitor] },
            deliver: { box.notices += $0 })
        alerts.evaluate()
        monitor.setRules([])
        alerts.evaluate()
        #expect(box.notices.map(\.event) == [.raised])
    }
}
