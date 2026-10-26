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

    /// Shapes differ, so the level is readable without color perception.
    var symbolName: String {
        switch self {
        case .unknown: "questionmark.circle.fill"
        case .ok: "checkmark.circle.fill"
        case .careful: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
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

/// A Glances level as colored symbol and secondary text. Yellow text is hard
/// to read on light backgrounds, so only the symbol carries the color.
struct LevelLabel: View {
    let level: Level?

    var body: some View {
        Label {
            Text(AlertText.level(level))
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: (level ?? .unknown).symbolName)
                .foregroundStyle((level ?? .unknown).color)
        }
    }
}

/// A labeled horizontal bar for a percentage, colored by its Glances level.
/// Inside a `MeterGroup`, the bars of all rows start at the same position.
struct MeterRow: View {
    let title: String
    let percent: Double?
    let level: Level
    var detail: String?

    @Environment(\.meterLabelWidth) private var labelWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                MeterLabel(title: title)
                UsageBar(fraction: (percent ?? 0) / 100, color: level.color)
                Text(Format.percent(percent))
                    .monospacedDigit()
                    .numericTransition(percent)
                    .frame(width: 44, alignment: .trailing)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.leading, labelWidth + 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([Format.percent(percent), detail].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Rows whose labels share one column as wide as the widest label, so the
/// bars line up and longer translations still fit.
struct MeterGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    @State private var labelWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .environment(\.meterLabelWidth, labelWidth)
        .onPreferenceChange(MeterLabelWidthKey.self) { labelWidth = $0 }
    }
}

/// The label of a row in a `MeterGroup`.
struct MeterLabel: View {
    let title: String

    @Environment(\.meterLabelWidth) private var width

    var body: some View {
        Text(title)
            .fixedSize()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MeterLabelWidthKey.self, value: proxy.size.width)
                }
            }
            .frame(minWidth: width, alignment: .leading)
    }
}

nonisolated private struct MeterLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension EnvironmentValues {
    @Entry var meterLabelWidth: CGFloat = 0
}
