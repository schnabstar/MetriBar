import Foundation

/// What the user asked notifications to do. Part of `Preferences`; off until
/// the user turns it on.
///
/// Decoding is tolerant, see `Preferences`.
public struct NotificationSettings: Codable, Sendable, Equatable {
    /// The level from which a value is reported.
    public enum Threshold: String, Codable, Sendable, CaseIterable {
        case warning
        case critical

        public var level: Level {
            switch self {
            case .warning: .warning
            case .critical: .critical
            }
        }
    }

    public var isEnabled = false
    public var threshold = Threshold.warning
    /// Report servers that cannot be reached, and their return.
    public var notifiesOffline = true
    /// Report when a value is back to normal.
    public var notifiesRecovery = false
    /// How long a problem has to last before it is reported, so a short
    /// spike does not.
    public var holdSeconds = 120
    public var quietHours = QuietHours()

    public static let holdChoices = [0, 60, 120, 300, 600]

    public init() {}

    public var holdTime: TimeInterval {
        TimeInterval(holdSeconds)
    }
}

/// A daily period without notifications, such as 22:00 to 07:00. Problems
/// that last beyond it are reported when it ends.
public struct QuietHours: Codable, Sendable, Equatable {
    public var isEnabled = false
    /// Minutes since midnight.
    public var startMinute = 22 * 60
    public var endMinute = 7 * 60

    public init() {}

    public init(isEnabled: Bool, startMinute: Int, endMinute: Int) {
        self.isEnabled = isEnabled
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// Whether `date` is inside the period; it may span midnight. An empty
    /// period (start equals end) never matches.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, startMinute != endMinute else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }
}

extension NotificationSettings {
    private enum CodingKeys: String, CodingKey {
        case isEnabled, threshold, notifiesOffline, notifiesRecovery, holdSeconds, quietHours
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? isEnabled
        threshold = (try? container.decodeIfPresent(Threshold.self, forKey: .threshold)) ?? threshold
        notifiesOffline = (try? container.decodeIfPresent(Bool.self, forKey: .notifiesOffline)) ?? notifiesOffline
        notifiesRecovery = (try? container.decodeIfPresent(Bool.self, forKey: .notifiesRecovery)) ?? notifiesRecovery
        holdSeconds = ((try? container.decodeIfPresent(Int.self, forKey: .holdSeconds)) ?? holdSeconds).clamped(
            0...3600)
        quietHours = (try? container.decodeIfPresent(QuietHours.self, forKey: .quietHours)) ?? quietHours
    }
}

extension QuietHours {
    private enum CodingKeys: String, CodingKey {
        case isEnabled, startMinute, endMinute
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? isEnabled
        startMinute = ((try? container.decodeIfPresent(Int.self, forKey: .startMinute)) ?? startMinute)
            .clamped(0...1439)
        endMinute = ((try? container.decodeIfPresent(Int.self, forKey: .endMinute)) ?? endMinute).clamped(0...1439)
    }
}

extension Int {
    fileprivate func clamped(_ range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
