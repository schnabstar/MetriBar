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
    /// Oldest first; a `nil` is a gap.
    var values: [Double?]
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
                if index == 0, let trend, trend.values.compactMap({ $0 }).count >= 2 {
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

/// A line through the values, the oldest on the left, broken at the gaps.
private nonisolated struct TrendShape: Shape {
    let values: [Double?]
    let range: ClosedRange<Double>?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for segment in TrendLayout.segments(values, range: range) {
            let points = segment.map {
                CGPoint(x: rect.minX + rect.width * $0.x, y: rect.maxY - rect.height * $0.y)
            }
            guard let first = points.first else { continue }
            path.move(to: first)
            // One sample alone is drawn as a dot (a zero-length line with round caps).
            if points.count == 1 { path.addLine(to: first) }
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        return path
    }
}
