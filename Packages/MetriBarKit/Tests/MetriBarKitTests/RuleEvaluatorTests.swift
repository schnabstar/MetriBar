import Foundation
import Testing

@testable import MetriBarKit

struct RuleEvaluatorTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(cpu: Double? = nil, memory: Double? = nil, disks: [String: Double] = [:]) -> ServerSnapshot {
        var snapshot = ServerSnapshot()
        if let memory {
            snapshot.memory = Reading(
                value: try! JSONDecoder().decode(Memory.self, from: Data(#"{"percent":\#(memory)}"#.utf8)))
        }
        if let cpu {
            snapshot.cpu = Reading(value: try! JSONDecoder().decode(CPU.self, from: Data(#"{"total":\#(cpu)}"#.utf8)))
        }
        if !disks.isEmpty {
            let items = disks.keys.sorted().map { mount in
                try! JSONDecoder().decode(
                    FileSystem.self, from: Data(#"{"mnt_point":"\#(mount)","percent":\#(disks[mount]!)}"#.utf8))
            }
            snapshot.fileSystems = ItemCollection(items: items)
        }
        return snapshot
    }

    private func levels(
        _ evaluator: inout RuleEvaluator, _ rules: [ThresholdRule], _ snapshot: ServerSnapshot,
        unavailable: Set<Feed> = [], at seconds: TimeInterval
    ) -> [Level] {
        evaluator.evaluate(
            rules: rules, snapshot: snapshot, unavailable: unavailable, now: start.addingTimeInterval(seconds)
        ).map(\.level)
    }

    @Test func firesAfterTheHoldTime() {
        let rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 90, holdSeconds: 300, severity: .critical)
        var evaluator = RuleEvaluator()
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 0) == [.ok])
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 299) == [.ok])
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 300) == [.critical])
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 400) == [.critical])
    }

    @Test func aDipBelowTheLimitStartsTheCountAnew() {
        let rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 90, holdSeconds: 300)
        var evaluator = RuleEvaluator()
        _ = levels(&evaluator, [rule], snapshot(cpu: 95), at: 0)
        _ = levels(&evaluator, [rule], snapshot(cpu: 80), at: 200)
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 250) == [.ok])
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 549) == [.ok])
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 550) == [.warning])
    }

    @Test func noHoldTimeFiresAtOnce() {
        let rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 90)
        var evaluator = RuleEvaluator()
        #expect(levels(&evaluator, [rule], snapshot(cpu: 91), at: 0) == [.warning])
    }

    @Test func staysFiringUntilTheValueIsBackByTheHysteresis() {
        let rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 90)
        var evaluator = RuleEvaluator()
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 0) == [.warning])
        // Below the limit but within the hysteresis: still firing.
        #expect(levels(&evaluator, [rule], snapshot(cpu: 89), at: 10) == [.warning])
        #expect(levels(&evaluator, [rule], snapshot(cpu: 88.5), at: 20) == [.warning])
        #expect(levels(&evaluator, [rule], snapshot(cpu: 87), at: 30) == [.ok])
        // Over the limit again: a new start, no hold time here.
        #expect(levels(&evaluator, [rule], snapshot(cpu: 91), at: 40) == [.warning])
    }

    @Test func eachMountPointHasItsOwnState() {
        let rule = ThresholdRule(metric: RuleMetric(.disk), limit: 85, holdSeconds: 60)
        var evaluator = RuleEvaluator()
        let first = snapshot(disks: ["/a": 90, "/b": 50])
        let conditions = evaluator.evaluate(rules: [rule], snapshot: first, now: start)
        #expect(conditions.map(\.level) == [.ok, .ok])
        #expect(Set(conditions.compactMap(\.item)).count == 2)

        // /b crosses later than /a.
        _ = evaluator.evaluate(
            rules: [rule], snapshot: snapshot(disks: ["/a": 90, "/b": 90]), now: start.addingTimeInterval(30))
        let later = evaluator.evaluate(
            rules: [rule], snapshot: snapshot(disks: ["/a": 90, "/b": 90]), now: start.addingTimeInterval(61))
        let byMount = Dictionary(uniqueKeysWithValues: later.map { ($0.rule?.itemName ?? "", $0.level) })
        #expect(byMount["/a"] == .warning)
        #expect(byMount["/b"] == .ok)
    }

    @Test func conditionsCarryTheRuleAndTheValue() throws {
        let rule = ThresholdRule(metric: RuleMetric(.disk, item: "/a"), comparison: .above, limit: 85)
        var evaluator = RuleEvaluator()
        let condition = try #require(
            evaluator.evaluate(rules: [rule], snapshot: snapshot(disks: ["/a": 91, "/b": 99]), now: start).first)
        #expect(condition.kind == .rule)
        #expect(condition.value == 91)
        #expect(
            condition.rule == Condition.RuleDetail(metric: rule.metric, comparison: .above, limit: 85, itemName: "/a"))
        #expect(condition.item?.hasPrefix(rule.id.uuidString) == true)
    }

    @Test func belowRulesWatchForLowValues() {
        let rule = ThresholdRule(metric: RuleMetric(.disk), comparison: .below, limit: 10, severity: .critical)
        var evaluator = RuleEvaluator()
        #expect(levels(&evaluator, [rule], snapshot(disks: ["/a": 5]), at: 0) == [.critical])
        #expect(levels(&evaluator, [rule], snapshot(disks: ["/a": 11]), at: 10) == [.critical])
        #expect(levels(&evaluator, [rule], snapshot(disks: ["/a": 13]), at: 20) == [.ok])
    }

    @Test func disabledRulesGiveNoConditionsAndForgetTheirState() {
        var rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 90, holdSeconds: 60)
        var evaluator = RuleEvaluator()
        _ = levels(&evaluator, [rule], snapshot(cpu: 95), at: 0)
        rule.isEnabled = false
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 100).isEmpty)
        // Turned on again: counting starts anew, the old start is not used.
        rule.isEnabled = true
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 200) == [.ok])
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 260) == [.warning])
    }

    @Test func aValueThatIsGoneIsForgotten() {
        let rule = ThresholdRule(metric: RuleMetric(.disk), limit: 85)
        var evaluator = RuleEvaluator()
        #expect(levels(&evaluator, [rule], snapshot(disks: ["/a": 90]), at: 0) == [.warning])
        #expect(levels(&evaluator, [rule], snapshot(disks: ["/b": 10]), at: 10) == [.ok])
        // /a is back and exceeds again from scratch.
        #expect(levels(&evaluator, [rule], snapshot(disks: ["/a": 70]), at: 20) == [.ok])
    }

    @Test func outdatedFeedsKeepTheStateAndRunNoTimer() {
        let rule = ThresholdRule(metric: RuleMetric(.disk), limit: 85, holdSeconds: 60)
        var evaluator = RuleEvaluator()
        let high = snapshot(disks: ["/a": 90])
        _ = levels(&evaluator, [rule], high, at: 0)
        // The storage feed fails for a long time: no timer, nothing fires.
        #expect(levels(&evaluator, [rule], high, unavailable: [.storage], at: 100) == [.ok])
        #expect(levels(&evaluator, [rule], high, unavailable: [.storage], at: 1000) == [.ok])
        #expect(levels(&evaluator, [rule], high, at: 1010) == [.ok])
        #expect(levels(&evaluator, [rule], high, at: 1070) == [.warning])
        // A firing rule keeps firing while its feed is down, and does not stop.
        #expect(
            levels(&evaluator, [rule], snapshot(disks: ["/a": 10]), unavailable: [.storage], at: 1100) == [.warning])
        #expect(levels(&evaluator, [rule], snapshot(disks: ["/a": 10]), at: 1110) == [.ok])
    }

    @Test func otherFeedsAreNotAffectedByAnOutdatedOne() {
        let rules = [
            ThresholdRule(metric: RuleMetric(.cpu), limit: 90),
            ThresholdRule(metric: RuleMetric(.disk), limit: 85),
        ]
        var evaluator = RuleEvaluator()
        let both = snapshot(cpu: 95, disks: ["/a": 90])
        #expect(levels(&evaluator, rules, both, unavailable: [.storage], at: 0) == [.warning])
    }

    @Test func manyRulesAtOnce() {
        let rules = [
            ThresholdRule(metric: RuleMetric(.cpu), limit: 90, severity: .critical),
            ThresholdRule(metric: RuleMetric(.cpu), limit: 50),
        ]
        var evaluator = RuleEvaluator()
        #expect(levels(&evaluator, rules, snapshot(cpu: 95), at: 0) == [.critical, .warning])
        // The first rule ends below its hysteresis, the second keeps firing.
        #expect(levels(&evaluator, rules, snapshot(cpu: 60), at: 10) == [.ok, .warning])
        #expect(levels(&evaluator, rules, snapshot(cpu: 89), at: 15) == [.ok, .warning])
        #expect(levels(&evaluator, rules, snapshot(cpu: 30), at: 20) == [.ok, .ok])
    }

    // MARK: - Interrupted observation

    @Test func suspendingForgetsThePendingStartButNotAFiringRule() {
        let rules = [
            ThresholdRule(metric: RuleMetric(.cpu), limit: 90, holdSeconds: 300),
            ThresholdRule(metric: RuleMetric(.disk), limit: 85),
        ]
        var evaluator = RuleEvaluator()
        let both = snapshot(cpu: 95, disks: ["/a": 90])
        // The disk rule fires at once, the CPU rule waits.
        #expect(levels(&evaluator, rules, both, at: 0) == [.ok, .warning])

        evaluator.suspend()
        // Ten minutes later: the CPU rule has not been watched since, so it starts anew.
        #expect(levels(&evaluator, rules, both, at: 600) == [.ok, .warning])
        #expect(levels(&evaluator, rules, both, at: 899) == [.ok, .warning])
        #expect(levels(&evaluator, rules, both, at: 900) == [.warning, .warning])
    }

    @Test func withoutSuspendingTheOutageWouldCount() {
        let rule = ThresholdRule(metric: RuleMetric(.cpu), limit: 90, holdSeconds: 300)
        var evaluator = RuleEvaluator()
        _ = levels(&evaluator, [rule], snapshot(cpu: 95), at: 0)
        // Documents why `suspend()` exists.
        #expect(levels(&evaluator, [rule], snapshot(cpu: 95), at: 600) == [.warning])
    }

    // MARK: - Edited rules

    @Test func aRuleEditedToAnotherMetricStartsFromScratch() {
        let id = UUID()
        let cpu = ThresholdRule(id: id, metric: RuleMetric(.cpu), limit: 90)
        var evaluator = RuleEvaluator()
        #expect(levels(&evaluator, [cpu], snapshot(cpu: 95), at: 0) == [.warning])

        // The same rule, now about the disk, with a hold time.
        let disk = ThresholdRule(id: id, metric: RuleMetric(.disk), limit: 50, holdSeconds: 60)
        let first = evaluator.evaluate(
            rules: [disk], snapshot: snapshot(cpu: 95, disks: ["/a": 70]), now: start.addingTimeInterval(10))
        #expect(first.map(\.level) == [.ok])
        #expect(first.first?.rule?.metric == RuleMetric(.disk))
        #expect(levels(&evaluator, [disk], snapshot(disks: ["/a": 70]), at: 69) == [.ok])
        #expect(levels(&evaluator, [disk], snapshot(disks: ["/a": 70]), at: 70) == [.warning])
    }

    /// Both measure one value of the whole server, so only the metric tells them apart.
    @Test func aFiringCPURuleEditedToMemoryDoesNotFireAtOnce() {
        let id = UUID()
        var evaluator = RuleEvaluator()
        let cpu = ThresholdRule(id: id, metric: RuleMetric(.cpu), limit: 90)
        #expect(levels(&evaluator, [cpu], snapshot(cpu: 95, memory: 60), at: 0) == [.warning])

        let memory = ThresholdRule(id: id, metric: RuleMetric(.memory), limit: 50, holdSeconds: 60)
        #expect(levels(&evaluator, [memory], snapshot(cpu: 95, memory: 60), at: 10) == [.ok])
        #expect(levels(&evaluator, [memory], snapshot(cpu: 95, memory: 60), at: 69) == [.ok])
        #expect(levels(&evaluator, [memory], snapshot(cpu: 95, memory: 60), at: 70) == [.warning])
    }

    @Test func aRuleEditedFromAboveToBelowStartsFromScratch() {
        let id = UUID()
        var evaluator = RuleEvaluator()
        let above = ThresholdRule(id: id, metric: RuleMetric(.cpu), comparison: .above, limit: 50)
        #expect(levels(&evaluator, [above], snapshot(cpu: 95), at: 0) == [.warning])
        let below = ThresholdRule(id: id, metric: RuleMetric(.cpu), comparison: .below, limit: 99, holdSeconds: 60)
        #expect(levels(&evaluator, [below], snapshot(cpu: 95), at: 10) == [.ok])
    }

    @Test func aRuleEditedToAnotherItemStartsFromScratch() {
        let id = UUID()
        var evaluator = RuleEvaluator()
        let all = ThresholdRule(id: id, metric: RuleMetric(.disk), limit: 85, holdSeconds: 60)
        _ = levels(&evaluator, [all], snapshot(disks: ["/a": 90]), at: 0)
        let one = ThresholdRule(id: id, metric: RuleMetric(.disk, item: "/a"), limit: 85, holdSeconds: 60)
        #expect(levels(&evaluator, [one], snapshot(disks: ["/a": 90]), at: 120) == [.ok])
    }

    @Test func conditionsOfAnEditedMetricHaveAnotherKeyForTheAlerts() {
        let id = UUID()
        var evaluator = RuleEvaluator()
        let cpu = evaluator.evaluate(
            rules: [ThresholdRule(id: id, metric: RuleMetric(.cpu), limit: 1)], snapshot: snapshot(cpu: 5), now: start)
        let disk = evaluator.evaluate(
            rules: [ThresholdRule(id: id, metric: RuleMetric(.disk), limit: 1)],
            snapshot: snapshot(disks: ["/a": 5]), now: start)
        #expect(cpu.first?.item != disk.first?.item)
    }

    @Test func aChangedLimitKeepsTheState() {
        let id = UUID()
        var evaluator = RuleEvaluator()
        let strict = ThresholdRule(id: id, metric: RuleMetric(.cpu), limit: 90, holdSeconds: 300)
        _ = levels(&evaluator, [strict], snapshot(cpu: 95), at: 0)
        // A small change of the limit does not make the rule wait all over again.
        let relaxed = ThresholdRule(id: id, metric: RuleMetric(.cpu), limit: 92, holdSeconds: 300)
        #expect(levels(&evaluator, [relaxed], snapshot(cpu: 95), at: 300) == [.warning])
    }
}
