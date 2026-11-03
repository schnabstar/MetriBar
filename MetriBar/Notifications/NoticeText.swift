import Foundation
import MetriBarKit

/// The words of a notification. The server name is the title, the body says
/// what changed.
nonisolated enum NoticeText {
    static func title(_ notice: AlertNotice) -> String {
        notice.serverName
    }

    static func body(_ notice: AlertNotice) -> String {
        let condition = notice.condition
        switch notice.event {
        case .offline:
            return String(localized: "Cannot be reached.")
        case .backOnline:
            return String(localized: "Can be reached again.")
        case .recovered:
            return String(localized: "\(subject(condition)): back to normal")
        case .raised, .escalated:
            let level = levelWord(condition.level)
            guard let value = value(condition) else {
                return String(localized: "\(subject(condition)): \(level)")
            }
            return String(localized: "\(subject(condition)): \(level) (\(value))")
        }
    }

    static func subject(_ condition: Condition) -> String {
        let item = condition.item ?? ""
        switch condition.kind {
        case .cpu: return String(localized: "CPU")
        case .memory: return String(localized: "Memory")
        case .load: return String(localized: "Load")
        case .container: return String(localized: "Container “\(item)”")
        case .sensor: return String(localized: "Temperature of “\(item)”")
        case .fileSystem: return String(localized: "Disk “\(item)”")
        case .rule: return condition.rule.map(RuleText.condition) ?? String(localized: "Rule")
        case .offline: return String(localized: "Connection")
        }
    }

    static func levelWord(_ level: Level) -> String {
        switch level {
        case .critical: String(localized: "critical")
        default: String(localized: "warning")
        }
    }

    static func value(_ condition: Condition) -> String? {
        guard condition.value != nil else { return nil }
        switch condition.kind {
        case .cpu, .memory, .fileSystem: return Format.percent(condition.value)
        case .sensor: return Format.temperature(condition.value, unit: "C")
        case .load: return Format.load(condition.value)
        case .rule: return condition.rule.flatMap { RuleText.value(condition.value, unit: $0.metric.kind.unit) }
        case .container, .offline: return nil
        }
    }
}
