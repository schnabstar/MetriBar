import Foundation

/// A value the menu bar can show next to the status icon.
public enum MenuBarMetric: String, Codable, Sendable, CaseIterable, Hashable {
    case cpu
    case memory
    case swap
    case load
    /// The hottest temperature sensor.
    case temperature
    /// The fullest file system.
    case disk
    case networkDown
    case networkUp
    /// How many containers report a problem.
    case containers

    /// At most this many values fit next to the icon.
    public static let maximumCount = 3

    /// The feed that delivers the value. Anything beyond the usual
    /// background feeds is fetched in the background while it is shown.
    public var feed: Feed {
        switch self {
        case .cpu, .memory, .load: .core
        case .swap, .disk: .storage
        case .temperature: .sensors
        case .networkDown, .networkUp: .network
        case .containers: .containers
        }
    }

    /// The rule metric that reads the same value, if there is one.
    var ruleMetric: RuleMetric.Kind? {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        case .swap: .swap
        case .load: .load
        case .temperature: .temperature
        case .disk: .disk
        case .networkDown: .networkDown
        case .networkUp: .networkUp
        case .containers: nil
        }
    }

    public static func requiredFeeds(_ items: [MenuBarMetric]) -> Set<Feed> {
        Set(items.map(\.feed)).subtracting(Feed.background)
    }
}

/// How the values look in the menu bar.
public enum MenuBarStyle: String, Codable, Sendable, CaseIterable {
    /// A small symbol before each value.
    case symbols
    /// A word before each value: "CPU 12 %".
    case labels
    /// The number alone.
    case valuesOnly
}

/// When the values are shown.
public enum MenuBarVisibility: String, Codable, Sendable, CaseIterable {
    case always
    /// Only while some server has a warning, an alert or is offline; the
    /// menu bar shows the status icon alone otherwise.
    case onlyOnProblems
}

/// One value of the menu bar, ready to show.
public struct MenuBarSegment: Sendable, Equatable {
    public var metric: MenuBarMetric
    public var value: Double
    /// The value with its unit, for example "42 %" or "1.2 MB/s".
    public var text: String
}

/// Reads the chosen values from a server's snapshot and formats them.
public enum MenuBarText {
    /// The segments of `items`, in their order and without duplicates. A
    /// value the server did not report is left out.
    public static func segments(
        _ items: [MenuBarMetric], from snapshot: ServerSnapshot, locale: Locale = .current
    ) -> [MenuBarSegment] {
        Preferences.normalized(items).compactMap { metric in
            guard let value = value(metric, from: snapshot) else { return nil }
            return MenuBarSegment(metric: metric, value: value, text: format(value, metric, locale: locale))
        }
    }

    public static func value(_ metric: MenuBarMetric, from snapshot: ServerSnapshot) -> Double? {
        guard let kind = metric.ruleMetric else {
            // Containers: the number with a problem; only if the feed was fetched.
            return snapshot.containers.map { Double($0.items.filter(\.isUnhealthy).count) }
        }
        let values = MetricReader.read(RuleMetric(kind), from: snapshot).map(\.value)
        switch metric {
        case .temperature, .disk: return values.max()
        default: return values.first
        }
    }

    public static func format(_ value: Double, _ metric: MenuBarMetric, locale: Locale = .current) -> String {
        switch metric {
        case .cpu, .memory, .swap, .disk:
            return (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
        case .load:
            return value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        case .temperature:
            return "\(value.formatted(.number.precision(.fractionLength(0)).locale(locale))) °C"
        case .networkDown, .networkUp:
            return rate(value * 1_000_000, locale: locale)
        case .containers:
            return value.formatted(.number.precision(.fractionLength(0)).locale(locale))
        }
    }

    /// Bytes per second in the unit that keeps the number short.
    static func rate(_ bytesPerSecond: Double, locale: Locale) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var number = max(bytesPerSecond, 0)
        var unit = 0
        while number >= 1000, unit < units.count - 1 {
            number /= 1000
            unit += 1
        }
        // One decimal below ten, none above, and no trailing zero: "1.5", "12", "1".
        let digits = (unit == 0 || number >= 10) ? 0...0 : 0...1
        return "\(number.formatted(.number.precision(.fractionLength(digits)).locale(locale))) \(units[unit])"
    }
}
