import MetriBarKit
import SwiftUI

extension ServerHealth {
    /// Symbols differ in shape, not only in color, so the state is readable
    /// in the template-rendered menu bar and without color perception.
    var symbolName: String {
        switch self {
        case .unknown: "server.rack"
        case .ok: "server.rack"
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon"
        case .offline: "network.slash"
        }
    }

    var color: Color {
        switch self {
        case .unknown: .secondary
        case .ok: .green
        case .warning: .orange
        case .critical: .red
        case .offline: .secondary
        }
    }

    var label: String {
        switch self {
        case .unknown: String(localized: "Connecting")
        case .ok: String(localized: "OK")
        case .warning: String(localized: "Warning")
        case .critical: String(localized: "Critical")
        case .offline: String(localized: "Offline")
        }
    }
}

extension Level {
    var color: Color {
        switch self {
        case .unknown: .accentColor
        case .ok: .green
        case .careful: .yellow
        case .warning: .orange
        case .critical: .red
        }
    }
}

/// Small colored status symbol for a server.
struct HealthBadge: View {
    let health: ServerHealth

    var body: some View {
        Image(systemName: health == .ok || health == .unknown ? "circle.fill" : health.symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(health.color)
            .imageScale(.small)
            .accessibilityLabel(health.label)
    }
}

/// A labeled horizontal bar for a percentage, colored by its Glances level.
struct MeterRow: View {
    let title: String
    let percent: Double?
    let level: Level
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(title)
                    .frame(width: 64, alignment: .leading)
                UsageBar(fraction: (percent ?? 0) / 100, color: level.color)
                Text(Format.percent(percent))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 72)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([Format.percent(percent), detail].compactMap { $0 }.joined(separator: ", "))
    }
}
