import Foundation

/// The app's settings, stored as one JSON value in UserDefaults.
///
/// Decoding is tolerant: a key that is missing, for example because the data
/// was written by an older version, falls back to its default instead of
/// failing and resetting every setting.
public struct Preferences: Codable, Sendable, Equatable {
    public enum MenuBarValue: String, Codable, Sendable, CaseIterable {
        case none, cpu, memory, cpuAndMemory
    }

    public var menuBarValue: MenuBarValue = .none
    /// Server whose value the menu bar shows; `nil` for the selected one.
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
        case menuBarValue, menuBarServerID, baseIntervalSeconds, liveIntervalSeconds, checksForUpdates, notifications
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` as well, so an unknown menu bar value does not reset the rest.
        menuBarValue = (try? container.decodeIfPresent(MenuBarValue.self, forKey: .menuBarValue)) ?? menuBarValue
        menuBarServerID = try? container.decodeIfPresent(UUID.self, forKey: .menuBarServerID)
        baseIntervalSeconds =
            try container.decodeIfPresent(Int.self, forKey: .baseIntervalSeconds) ?? baseIntervalSeconds
        liveIntervalSeconds =
            try container.decodeIfPresent(Int.self, forKey: .liveIntervalSeconds) ?? liveIntervalSeconds
        checksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checksForUpdates) ?? checksForUpdates
        notifications =
            (try? container.decodeIfPresent(NotificationSettings.self, forKey: .notifications)) ?? notifications
    }
}
