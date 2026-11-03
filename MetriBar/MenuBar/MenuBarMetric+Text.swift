import Foundation
import MetriBarKit

/// How the menu bar values are named and drawn.
extension MenuBarMetric {
    /// The full name, for the settings and for VoiceOver.
    var title: String {
        switch self {
        case .cpu: String(localized: "CPU usage")
        case .memory: String(localized: "Memory usage")
        case .swap: String(localized: "Swap usage")
        case .load: String(localized: "Load (5 minutes)")
        case .temperature: String(localized: "Highest temperature")
        case .disk: String(localized: "Fullest disk")
        case .networkDown: String(localized: "Network download")
        case .networkUp: String(localized: "Network upload")
        case .containers: String(localized: "Containers with problems")
        }
    }

    /// The short word before the value in the "labels" style.
    var label: String {
        switch self {
        case .cpu: String(localized: "CPU")
        case .memory: String(localized: "RAM")
        case .swap: String(localized: "Swap")
        case .load: String(localized: "Load")
        case .temperature: String(localized: "Temp")
        case .disk: String(localized: "Disk")
        case .networkDown: "↓"
        case .networkUp: "↑"
        case .containers: String(localized: "Containers")
        }
    }

    /// The symbol before the value in the "symbols" style. Network values
    /// carry their arrow in every style, because a rate alone says nothing.
    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .swap: "arrow.triangle.swap"
        case .load: "gauge.with.dots.needle.33percent"
        case .temperature: "thermometer.medium"
        case .disk: "internaldrive"
        case .networkDown: "arrow.down"
        case .networkUp: "arrow.up"
        case .containers: "shippingbox"
        }
    }

    var isNetwork: Bool {
        self == .networkDown || self == .networkUp
    }
}

extension MenuBarStyle {
    var title: String {
        switch self {
        case .symbols: String(localized: "Symbols")
        case .labels: String(localized: "Words")
        case .valuesOnly: String(localized: "Numbers only")
        }
    }
}

extension MenuBarVisibility {
    var title: String {
        switch self {
        case .always: String(localized: "Always")
        case .onlyOnProblems: String(localized: "Only when something is wrong")
        }
    }
}
