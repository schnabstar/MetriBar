import Foundation
import Testing

@testable import MetriBarKit

struct PreferencesTests {
    @Test func roundTrips() throws {
        var preferences = Preferences()
        preferences.menuBarValue = .cpuAndMemory
        preferences.menuBarServerID = UUID()
        preferences.baseIntervalSeconds = 30
        preferences.liveIntervalSeconds = 1
        preferences.checksForUpdates = true
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(decoded == preferences)
    }

    /// Written by MetriBar 0.11.0, before the update check existed.
    @Test func decodesTheFormatOf011() throws {
        let json = Data(
            #"{"menuBarValue":"cpu","baseIntervalSeconds":30,"liveIntervalSeconds":5}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(preferences.menuBarValue == .cpu)
        #expect(preferences.baseIntervalSeconds == 30)
        #expect(preferences.liveIntervalSeconds == 5)
        #expect(preferences.checksForUpdates == false)
    }

    @Test func emptyObjectGivesDefaults() throws {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(preferences == Preferences())
        #expect(!preferences.checksForUpdates)
    }

    @Test func unknownMenuBarValueKeepsTheOtherSettings() throws {
        let json = Data(#"{"menuBarValue":"network","baseIntervalSeconds":60}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(preferences.menuBarValue == .none)
        #expect(preferences.baseIntervalSeconds == 60)
    }

    @Test func updateCheckIsOffByDefault() {
        #expect(Preferences().checksForUpdates == false)
    }
}
