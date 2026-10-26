import MetriBarKit
import SwiftUI

/// A thin rounded bar for a fraction from 0 to 1.
struct UsageBar: View {
    let fraction: Double
    var color: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: geometry.size.width * min(max(fraction.isFinite ? fraction : 0, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A ring with the value in the center, colored by its Glances level.
struct RingGauge: View {
    let title: String
    /// 0 … 100
    let percent: Double?
    let level: Level
    /// Text in the center, usually the percentage.
    let value: String
    var detail: String?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(level.color.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 14)
            }
            .frame(width: 104, height: 104)
            Text(title)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ", "))
    }

    private var fraction: Double {
        guard let percent, percent.isFinite else { return 0 }
        return min(max(percent / 100, 0), 1)
    }
}
