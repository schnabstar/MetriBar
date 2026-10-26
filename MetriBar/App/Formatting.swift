import Foundation

/// Locale-aware formatting of Glances values. `nil` becomes an en dash.
/// Pure functions, usable from any isolation.
nonisolated enum Format {
    static let placeholder = "–"

    /// Glances percentages (0…100) as "37 %".
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        return (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    static func bytes(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return placeholder }
        return Int64(value).formatted(.byteCount(style: .memory))
    }

    static func bytesPerSecond(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return placeholder }
        return String(localized: "\(Int64(value).formatted(.byteCount(style: .decimal)))/s")
    }

    /// Glances reports container network rates in bits per second.
    static func bitsPerSecond(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return placeholder }
        return bytesPerSecond(value / 8)
    }

    static func load(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        return value.formatted(.number.precision(.fractionLength(2)))
    }

    /// "12 d 4 h", at most two units.
    static func duration(_ duration: Duration?) -> String {
        guard let duration, duration > .zero else { return placeholder }
        return duration.formatted(
            .units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }

    static func temperature(_ value: Double?, unit: String?) -> String {
        guard let value, value.isFinite else { return placeholder }
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        switch unit?.uppercased() {
        case "C", nil: return "\(number) °C"
        case "F": return "\(number) °F"
        default: return "\(number) \(unit ?? "")"
        }
    }

    static func number(_ value: Double?, fractionDigits: Int = 0) -> String {
        guard let value, value.isFinite else { return placeholder }
        return value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return placeholder }
        return date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .standard)
    }

    static func relative(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return placeholder }
        if now.timeIntervalSince(date) < 5 { return String(localized: "just now") }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}
