import Foundation
import Testing

@testable import MetriBarKit

struct NotificationSettingsTests {
    @Test func offByDefault() {
        let settings = NotificationSettings()
        #expect(!settings.isEnabled)
        #expect(!settings.quietHours.isEnabled)
        #expect(settings.threshold == .warning)
        #expect(settings.notifiesOffline)
        #expect(!settings.notifiesRecovery)
        #expect(Preferences().notifications == settings)
    }

    @Test func roundTrips() throws {
        var settings = NotificationSettings()
        settings.isEnabled = true
        settings.threshold = .critical
        settings.notifiesRecovery = true
        settings.holdSeconds = 300
        settings.quietHours = QuietHours(isEnabled: true, startMinute: 23 * 60, endMinute: 6 * 60 + 30)
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func tolerantDecoding() throws {
        let empty = try JSONDecoder().decode(NotificationSettings.self, from: Data("{}".utf8))
        #expect(empty == NotificationSettings())

        let json = Data(
            #"{"isEnabled":true,"threshold":"fatal","holdSeconds":-5,"quietHours":{"startMinute":99999}}"#.utf8)
        let settings = try JSONDecoder().decode(NotificationSettings.self, from: json)
        #expect(settings.isEnabled)
        #expect(settings.threshold == .warning)
        #expect(settings.holdSeconds == 0)
        #expect(settings.quietHours.startMinute == 1439)
        #expect(settings.quietHours.endMinute == 7 * 60)
    }

    @Test func preferencesOf0110HaveNotificationsOff() throws {
        let json = Data(
            #"{"menuBarValue":"cpu","baseIntervalSeconds":30,"liveIntervalSeconds":5,"checksForUpdates":true}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(preferences.notifications == NotificationSettings())
        #expect(preferences.checksForUpdates)
        #expect(preferences.baseIntervalSeconds == 30)
    }

    @Test func brokenNotificationSettingsDoNotResetThePreferences() throws {
        let json = Data(#"{"baseIntervalSeconds":60,"notifications":"on"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(preferences.notifications == NotificationSettings())
        #expect(preferences.baseIntervalSeconds == 60)
    }
}
