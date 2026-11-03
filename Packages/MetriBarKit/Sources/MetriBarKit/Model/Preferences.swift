import Foundation

/// The app's settings, stored as one JSON value in UserDefaults.
///
/// Decoding is tolerant: a key that is missing, for example because the data
/// was written by an older version, falls back to its default instead of
/// failing and resetting every setting.
public struct Preferences: Codable, Sendable, Equatable {
    /// The values next to the status icon, at most `MenuBarMetric.maximumCount`.
    public var menuBarItems: [MenuBarMetric] = []
    public var menuBarStyle = MenuBarStyle.symbols
    public var menuBarVisibility = MenuBarVisibility.always
    /// A small trend line after the first value.
    public var menuBarTrend = false
    /// Server whose values the menu bar shows; `nil` for the selected one.
    public var menuBarServerID: UUID?
    public var baseIntervalSeconds = 10
    public var liveIntervalSeconds = 2
    /// Ask GitHub about new releases of MetriBar. Off until the user turns it on.
    public var checksForUpdates = false
    public var notifications = NotificationSettings()

    public static let baseIntervalChoices = [5, 10, 30, 60]
    public static let liveIntervalChoices = [1, 2, 5]

    public init() {}

    public var pollingSettings: PollingSettings {
        PollingSettings(baseInterval: .seconds(baseIntervalSeconds), liveInterval: .seconds(liveIntervalSeconds))
    }
}

extension Preferences {
    private enum CodingKeys: String, CodingKey {
        case menuBarItems, menuBarStyle, menuBarVisibility, menuBarTrend, menuBarServerID
        case baseIntervalSeconds, liveIntervalSeconds, checksForUpdates, notifications
    }

    /// Read only: MetriBar 0.11.0 stored one of a few fixed combinations.
    private enum LegacyKeys: String, CodingKey {
        case menuBarValue
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        menuBarServerID = try? container.decodeIfPresent(UUID.self, forKey: .menuBarServerID)
        baseIntervalSeconds =
            try container.decodeIfPresent(Int.self, forKey: .baseIntervalSeconds) ?? baseIntervalSeconds
        liveIntervalSeconds =
            try container.decodeIfPresent(Int.self, forKey: .liveIntervalSeconds) ?? liveIntervalSeconds
        checksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checksForUpdates) ?? checksForUpdates
        notifications =
            (try? container.decodeIfPresent(NotificationSettings.self, forKey: .notifications)) ?? notifications
        menuBarStyle = (try? container.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle)) ?? menuBarStyle
        menuBarVisibility =
            (try? container.decodeIfPresent(MenuBarVisibility.self, forKey: .menuBarVisibility)) ?? menuBarVisibility

        menuBarTrend = (try? container.decodeIfPresent(Bool.self, forKey: .menuBarTrend)) ?? menuBarTrend

        if container.contains(.menuBarItems) {
            // A value of a later version is dropped, the others stay.
            let items = (try? container.decode(LossyArray<MenuBarMetric>.self, forKey: .menuBarItems))?.elements ?? []
            menuBarItems = Self.normalized(items)
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
            let value = try? legacy.decodeIfPresent(String.self, forKey: .menuBarValue)
        {
            // 0.11.0 showed a single value without a label, and two with labels.
            switch value {
            case "cpu": (menuBarItems, menuBarStyle) = ([.cpu], .valuesOnly)
            case "memory": (menuBarItems, menuBarStyle) = ([.memory], .valuesOnly)
            case "cpuAndMemory": (menuBarItems, menuBarStyle) = ([.cpu, .memory], .labels)
            default: break
            }
        }
    }

    /// No duplicates, at most as many as fit.
    public static func normalized(_ items: [MenuBarMetric]) -> [MenuBarMetric] {
        var seen: Set<MenuBarMetric> = []
        return Array(items.filter { seen.insert($0).inserted }.prefix(MenuBarMetric.maximumCount))
    }
}
