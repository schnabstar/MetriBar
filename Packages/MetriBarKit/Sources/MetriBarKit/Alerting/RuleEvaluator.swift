import Foundation

/// Turns the rules into conditions, with the hold time and the hysteresis.
///
/// A rule fires when its value has been on the wrong side of the limit for
/// the hold time, and stops when it is back by the hysteresis. Each value
/// (each mount point, each sensor) has its own state. The resulting
/// conditions have the level of the rule while it fires and `ok` otherwise;
/// the hold time is already applied, so `AlertEvaluator` does not wait again.
public struct RuleEvaluator: Sendable {
    /// A rule that is edited to measure something else starts from scratch:
    /// the state belongs to what is measured, not only to the rule's id.
    private struct Key: Hashable {
        var rule: UUID
        var metric: RuleMetric
        var comparison: ThresholdRule.Comparison
        var item: String?
    }

    private struct State {
        var since: Date?
        var firing = false
    }

    private var states: [Key: State] = [:]

    public init() {}

    /// Forgets the start of every rule that is waiting for its hold time,
    /// because the observation was interrupted: the connection failed, or
    /// the Mac slept. A rule that already fires keeps firing.
    public mutating func suspend() {
        for key in states.keys where states[key]?.firing != true {
            states[key]?.since = nil
        }
    }

    /// - Parameters:
    ///   - unavailable: Feeds without current data. Rules on them keep their
    ///     state: no timer runs on outdated values, and a firing rule does
    ///     not stop because its feed failed.
    public mutating func evaluate(
        rules: [ThresholdRule], snapshot: ServerSnapshot, unavailable: Set<Feed> = [], now: Date
    ) -> [Condition] {
        var conditions: [Condition] = []
        var keep: Set<Key> = []

        for rule in rules where rule.isEnabled {
            let detail = { (item: String?) in
                Condition.RuleDetail(
                    metric: rule.metric, comparison: rule.comparison, limit: rule.limit, itemName: item)
            }

            if unavailable.contains(rule.metric.kind.feed) {
                for key in states.keys
                where key.rule == rule.id && key.metric == rule.metric && key.comparison == rule.comparison {
                    keep.insert(key)
                    // A start time from before the outage must not count.
                    if states[key]?.firing != true { states[key]?.since = nil }
                    let level: Level = states[key]?.firing == true ? rule.severity.level : .ok
                    conditions.append(
                        Condition(.rule, item: Self.itemKey(key), level: level, rule: detail(key.item)))
                }
                continue
            }

            for reading in MetricReader.read(rule.metric, from: snapshot) {
                let key = Key(rule: rule.id, metric: rule.metric, comparison: rule.comparison, item: reading.item)
                keep.insert(key)
                var state = states[key] ?? State()
                if state.firing {
                    if rule.isCleared(by: reading.value) { state = State() }
                } else if rule.isViolated(by: reading.value) {
                    let since = state.since ?? now
                    state.since = since
                    if now.timeIntervalSince(since) >= TimeInterval(rule.holdSeconds) { state.firing = true }
                } else {
                    state.since = nil
                }
                states[key] = state
                conditions.append(
                    Condition(
                        .rule, item: Self.itemKey(key), level: state.firing ? rule.severity.level : .ok,
                        value: reading.value, rule: detail(reading.item)))
            }
        }

        // Rules that were deleted or turned off, values that are gone.
        for key in states.keys where !keep.contains(key) {
            states[key] = nil
        }
        return conditions
    }

    /// Identifies the value of a rule among the conditions of a server.
    private static func itemKey(_ key: Key) -> String {
        "\(key.rule.uuidString)|\(key.metric.kind.rawValue)|\(key.item ?? "")"
    }
}
