import AppKit
import MetriBarKit
import SwiftUI

/// Draws what the menu bar shows as one template image.
///
/// `MenuBarExtra` turns its label into a status item with one image and one
/// text: a label with several symbols and values loses all but the first.
/// One image has no such limit, and it can hold a sparkline. As a template
/// image it takes the color of the menu bar, in light and dark mode and over
/// every wallpaper, like the system's own symbols.
@MainActor
enum MenuBarImage {
    /// The height of the image; the menu bar is 24 points high on most Macs.
    static let height: CGFloat = 18

    static func render(
        health: ServerHealth, segments: [MenuBarSegment], style: MenuBarStyle, trend: TrendLine? = nil,
        scale: CGFloat? = nil
    ) -> NSImage {
        let content = MenuBarContent(health: health, segments: segments, style: style, trend: trend)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale ?? NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: height, height: height))
        image.isTemplate = true
        return image
    }
}

/// The recent values of the first menu bar item, drawn after it.
struct TrendLine: Equatable {
    var values: [Double]
    /// Percentages over 0 to 100; `nil` fits the line to its values.
    var range: ClosedRange<Double>?
}

/// The view that is rendered. Colors do not matter for a template image,
/// only the alpha does.
struct MenuBarContent: View {
    let health: ServerHealth
    let segments: [MenuBarSegment]
    let style: MenuBarStyle
    var trend: TrendLine?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: health.symbolName)
            ForEach(Array(segments.enumerated()), id: \.element.metric) { index, segment in
                SegmentContent(segment: segment, style: style)
                if index == 0, let trend, trend.values.count >= 2 {
                    TrendShape(values: trend.values, range: trend.range)
                        .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 26, height: 11)
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.black)
        .frame(height: MenuBarImage.height)
        .fixedSize()
    }
}

private struct SegmentContent: View {
    let segment: MenuBarSegment
    let style: MenuBarStyle

    var body: some View {
        switch style {
        case .symbols:
            HStack(spacing: 2) {
                Image(systemName: segment.metric.symbolName)
                value
            }
        case .labels:
            HStack(spacing: 3) {
                Text(segment.metric.label)
                value
            }
        case .valuesOnly:
            if segment.metric.isNetwork {
                HStack(spacing: 1) {
                    Text(segment.metric.label)
                    value
                }
            } else {
                value
            }
        }
    }

    private var value: some View {
        Text(segment.text).monospacedDigit()
    }
}

/// A line through the values, the oldest on the left.
private nonisolated struct TrendShape: Shape {
    let values: [Double]
    let range: ClosedRange<Double>?

    func path(in rect: CGRect) -> Path {
        let low = range?.lowerBound ?? (values.min() ?? 0)
        var high = range?.upperBound ?? (values.max() ?? 1)
        // A flat line has no height to scale to: draw it in the middle.
        let flat = high - low < 0.000_001
        if flat { high = low + 1 }
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1)
            let fraction = flat ? 0.5 : min(max((value - low) / (high - low), 0), 1)
            let point = CGPoint(x: x, y: rect.maxY - rect.height * CGFloat(fraction))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
