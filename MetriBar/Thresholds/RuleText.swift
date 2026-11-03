import Foundation
import MetriBarKit

/// The words for rules: in the list, in the editor and in notifications.
nonisolated enum RuleText {
    static func kindName(_ kind: RuleMetric.Kind) -> String {
        switch kind {
        case .cpu: String(localized: "CPU usage")
        case .memory: String(localized: "Memory usage")
        case .swap: String(localized: "Swap usage")
        case .load: String(localized: "Load (5 minutes)")
        case .disk: String(localized: "Disk usage")
        case .temperature: String(localized: "Temperature")
        case .networkDown: String(localized: "Network download")
        case .networkUp: String(localized: "Network upload")
        }
    }

    /// The metric, with the mount point or sensor if the rule is about one.
    static func metricName(_ metric: RuleMetric, itemName: String? = nil) -> String {
        guard let item = itemName ?? metric.item else { return kindName(metric.kind) }
        switch metric.kind {
        case .disk: return String(localized: "Disk usage of “\(item)”")
        case .temperature: return String(localized: "Temperature of “\(item)”")
        default: return kindName(metric.kind)
        }
    }

    static func unitSymbol(_ unit: RuleMetric.Unit) -> String {
        switch unit {
        case .percent: "%"
        case .load: ""
        case .celsius: "°C"
        case .megabytesPerSecond: "MB/s"
        }
    }

    /// A value or limit with its unit.
    static func value(_ value: Double?, unit: RuleMetric.Unit) -> String? {
        guard let value, value.isFinite else { return nil }
        switch unit {
        case .percent: return Format.percent(value)
        case .load: return Format.load(value)
        case .celsius: return Format.temperature(value, unit: "C")
        case .megabytesPerSecond: return String(localized: "\(Format.number(value, fractionDigits: 1)) MB/s")
        }
    }

    /// "CPU usage above 90 %"
    static func condition(_ detail: Condition.RuleDetail) -> String {
        sentence(
            metric: detail.metric, comparison: detail.comparison, limit: detail.limit, itemName: detail.itemName)
    }

    static func sentence(
        metric: RuleMetric, comparison: ThresholdRule.Comparison, limit: Double, itemName: String? = nil
    ) -> String {
        let name = metricName(metric, itemName: itemName)
        let limit = value(limit, unit: metric.kind.unit) ?? "–"
        switch comparison {
        case .above: return String(localized: "\(name) above \(limit)")
        case .below: return String(localized: "\(name) below \(limit)")
        }
    }

    /// "CPU usage above 90 % for 5 minutes"
    static func summary(_ rule: ThresholdRule) -> String {
        let base = sentence(metric: rule.metric, comparison: rule.comparison, limit: rule.limit)
        guard rule.holdSeconds > 0 else { return base }
        return String(localized: "\(base) for \(duration(rule.holdSeconds))")
    }

    static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }

    static func holdLabel(_ seconds: Int) -> String {
        seconds == 0 ? String(localized: "Immediately") : duration(seconds)
    }

    static func severityLabel(_ severity: ThresholdRule.Severity) -> String {
        switch severity {
        case .warning: String(localized: "Warning")
        case .critical: String(localized: "Critical")
        }
    }

    static func comparisonLabel(_ comparison: ThresholdRule.Comparison) -> String {
        switch comparison {
        case .above: String(localized: "Above")
        case .below: String(localized: "Below")
        }
    }

    /// A limit that makes sense for the metric, for a new rule.
    static func defaultLimit(_ kind: RuleMetric.Kind) -> Double {
        switch kind {
        case .cpu, .memory: 90
        case .swap: 50
        case .load: 4
        case .disk: 85
        case .temperature: 80
        case .networkDown, .networkUp: 50
        }
    }

    /// The range a limit may have.
    static func limitRange(_ kind: RuleMetric.Kind) -> ClosedRange<Double> {
        switch kind.unit {
        case .percent: 0...100
        case .load: 0...1000
        case .celsius: -50...200
        case .megabytesPerSecond: 0...100_000
        }
    }
}

/// Starting points for new rules.
struct RuleTemplate: Identifiable {
    let id: String
    let title: String
    let rule: ThresholdRule

    @MainActor
    static var all: [RuleTemplate] {
        [
            RuleTemplate(
                id: "cpu", title: String(localized: "CPU above 90 % for 5 minutes"),
                rule: ThresholdRule(metric: RuleMetric(.cpu), limit: 90, holdSeconds: 300)),
            RuleTemplate(
                id: "memory", title: String(localized: "Memory above 90 % for 5 minutes"),
                rule: ThresholdRule(metric: RuleMetric(.memory), limit: 90, holdSeconds: 300)),
            RuleTemplate(
                id: "disk", title: String(localized: "A disk above 85 %"),
                rule: ThresholdRule(metric: RuleMetric(.disk), limit: 85, severity: .critical)),
            RuleTemplate(
                id: "temperature", title: String(localized: "Temperature above 80 °C for 1 minute"),
                rule: ThresholdRule(metric: RuleMetric(.temperature), limit: 80, holdSeconds: 60)),
            RuleTemplate(
                id: "swap", title: String(localized: "Swap above 50 % for 5 minutes"),
                rule: ThresholdRule(metric: RuleMetric(.swap), limit: 50, holdSeconds: 300)),
        ]
    }
}
