import Foundation
import Testing

@testable import MetriBarKit

struct PreferencesTests {
    @Test func roundTrips() throws {
        var preferences = Preferences()
        preferences.menuBarItems = [.cpu, .networkDown]
        preferences.menuBarStyle = .labels
        preferences.menuBarVisibility = .onlyOnProblems
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
        #expect(preferences.menuBarItems == [.cpu])
        #expect(preferences.menuBarStyle == .valuesOnly)
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
        #expect(preferences.menuBarItems.isEmpty)
        #expect(preferences.baseIntervalSeconds == 60)
    }

    /// 0.11.0 stored one of four combinations in `menuBarValue`.
    @Test(arguments: [
        ("none", [MenuBarMetric](), MenuBarStyle.symbols),
        ("cpu", [.cpu], .valuesOnly),
        ("memory", [.memory], .valuesOnly),
        ("cpuAndMemory", [.cpu, .memory], .labels),
    ])
    func migratesTheMenuBarValueOf011(value: String, items: [MenuBarMetric], style: MenuBarStyle) throws {
        let json = Data(#"{"menuBarValue":"\#(value)","menuBarServerID":"\#(UUID().uuidString)"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(preferences.menuBarItems == items)
        #expect(preferences.menuBarStyle == style)
        #expect(preferences.menuBarServerID != nil)
        #expect(preferences.menuBarVisibility == .always)
    }

    @Test func theNewFormatWinsOverTheOld() throws {
        let json = Data(#"{"menuBarValue":"cpu","menuBarItems":["load"],"menuBarStyle":"symbols"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(preferences.menuBarItems == [.load])
        #expect(preferences.menuBarStyle == .symbols)
    }

    @Test func migratedPreferencesDoNotWriteTheOldKey() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"menuBarValue":"cpuAndMemory"}"#.utf8))
        let data = try JSONEncoder().encode(old)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("menuBarValue"))
        #expect(try JSONDecoder().decode(Preferences.self, from: data) == old)
    }

    @Test func menuBarItemsAreTolerantAndLimited() throws {
        let json = Data(#"{"menuBarItems":["cpu","quantum","cpu","memory","load","swap"],"menuBarStyle":"huge"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: json)
        // A value of a later version and a duplicate are dropped, three fit.
        #expect(preferences.menuBarItems == [.cpu, .memory, .load])
        #expect(preferences.menuBarStyle == .symbols)
    }

    @Test func menuBarDefaultsShowNothingButTheIcon() {
        let preferences = Preferences()
        #expect(preferences.menuBarItems.isEmpty)
        #expect(preferences.menuBarVisibility == .always)
    }

    @Test func updateCheckIsOffByDefault() {
        #expect(Preferences().checksForUpdates == false)
    }
}
