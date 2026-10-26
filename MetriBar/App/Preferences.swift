import Foundation
import MetriBarKit
import ServiceManagement

struct Preferences: Codable, Equatable {
    enum MenuBarValue: String, Codable, CaseIterable {
        case none, cpu, memory
    }

    var menuBarValue: MenuBarValue = .none
    /// Server whose value the menu bar shows; `nil` for the selected one.
    var menuBarServerID: UUID?
    var baseIntervalSeconds = 10
    var liveIntervalSeconds = 2

    static let baseIntervalChoices = [5, 10, 30, 60]
    static let liveIntervalChoices = [1, 2, 5]

    var pollingSettings: PollingSettings {
        PollingSettings(baseInterval: .seconds(baseIntervalSeconds), liveInterval: .seconds(liveIntervalSeconds))
    }
}

/// Launch at login through `SMAppService`. Off unless the user turns it on.
enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
