import Foundation
import Testing

@testable import MetriBarKit

@MainActor
struct ThresholdRuleTests {
    @Test func roundTrips() throws {
        let rule = ThresholdRule(
            serverID: UUID(), metric: RuleMetric(.disk, item: "/mnt/data"), comparison: .above, limit: 85,
            holdSeconds: 300, severity: .critical, isEnabled: false)
        let decoded = try JSONDecoder().decode(ThresholdRule.self, from: JSONEncoder().encode(rule))
        #expect(decoded == rule)
    }

    @Test func onlyMetricAndLimitAreRequired() throws {
        let json = Data(#"{"metric":{"kind":"cpu"},"limit":90}"#.utf8)
        let rule = try JSONDecoder().decode(ThresholdRule.self, from: json)
        #expect(rule.metric == RuleMetric(.cpu))
        #expect(rule.limit == 90)
        #expect(rule.comparison == .above)
        #expect(rule.severity == .warning)
        #expect(rule.holdSeconds == 0)
        #expect(rule.isEnabled)
        #expect(rule.serverID == nil)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ThresholdRule.self, from: Data(#"{"limit":90}"#.utf8))
        }
    }

    @Test func tolerantAboutBrokenOptionalFields() throws {
        let json = Data(
            #"{"metric":{"kind":"memory"},"limit":80,"comparison":"sideways","severity":"fatal","holdSeconds":-5}"#.utf8
        )
        let rule = try JSONDecoder().decode(ThresholdRule.self, from: json)
        #expect(rule.comparison == .above)
        #expect(rule.severity == .warning)
        #expect(rule.holdSeconds == 0)
    }

    @Test func aMetricOfALaterVersionFailsOnlyThatRule() throws {
        let suite = "ThresholdRuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let stored =
            #"{"version":2,"rules":[{"metric":{"kind":"cpu"},"limit":90},{"metric":{"kind":"quantum"},"limit":1},{"metric":{"kind":"swap"},"limit":50}]}"#
        defaults.set(Data(stored.utf8), forKey: "rules")
        let rules = RuleStore(defaults: defaults).load()
        #expect(rules.map(\.metric.kind) == [.cpu, .swap])
    }

    @Test func storeSavesAndLoads() {
        let suite = "ThresholdRuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RuleStore(defaults: defaults)
        #expect(store.load().isEmpty)
        let rules = [
            ThresholdRule(metric: RuleMetric(.cpu), limit: 90, holdSeconds: 300),
            ThresholdRule(metric: RuleMetric(.temperature), limit: 80, severity: .critical),
        ]
        store.save(rules)
        #expect(store.load() == rules)
    }

    @Test func onlyDiskAndTemperatureHaveItems() {
        #expect(RuleMetric(.cpu, item: "x").item == nil)
        #expect(RuleMetric(.disk, item: "/").item == "/")
        #expect(RuleMetric(.temperature, item: "Composite").item == "Composite")
        #expect(RuleMetric.Kind.allCases.filter(\.supportsItem) == [.disk, .temperature])
    }

    @Test func appliesToItsServerOrToAll() {
        let server = UUID()
        let other = UUID()
        let everywhere = ThresholdRule(metric: RuleMetric(.cpu), limit: 90)
        let here = ThresholdRule(serverID: server, metric: RuleMetric(.cpu), limit: 90)
        let off = ThresholdRule(metric: RuleMetric(.cpu), limit: 90, isEnabled: false)
        #expect(everywhere.appliesTo(server) && everywhere.appliesTo(other))
        #expect(here.appliesTo(server) && !here.appliesTo(other))
        #expect(!off.appliesTo(server))
    }

    @Test func comparesStrictlyAndWithHysteresis() {
        let above = ThresholdRule(metric: RuleMetric(.cpu), comparison: .above, limit: 90)
        #expect(above.isViolated(by: 90.1))
        #expect(!above.isViolated(by: 90))
        // Percent: three points back from the limit.
        #expect(!above.isCleared(by: 88))
        #expect(above.isCleared(by: 87))

        let below = ThresholdRule(metric: RuleMetric(.cpu), comparison: .below, limit: 10)
        #expect(below.isViolated(by: 9.9))
        #expect(!below.isViolated(by: 10))
        #expect(!below.isCleared(by: 12))
        #expect(below.isCleared(by: 13))

        let load = ThresholdRule(metric: RuleMetric(.load), limit: 4)
        #expect(!load.isCleared(by: 3.9))
        #expect(load.isCleared(by: 3.8))
    }

    @Test func requiredFeedsAreOnlyTheOnesBeyondTheBackgroundSet() {
        let rules = [
            ThresholdRule(metric: RuleMetric(.cpu), limit: 90),
            ThresholdRule(metric: RuleMetric(.disk), limit: 85),
            ThresholdRule(metric: RuleMetric(.networkDown), limit: 50),
            ThresholdRule(metric: RuleMetric(.swap), limit: 50, isEnabled: false),
            ThresholdRule(metric: RuleMetric(.temperature), limit: 80),
        ]
        #expect(ThresholdRule.requiredFeeds(rules) == [.storage, .network])
        #expect(ThresholdRule.requiredFeeds([]).isEmpty)
    }
}
