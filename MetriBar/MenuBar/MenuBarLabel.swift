import MetriBarKit
import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let segments = segments
        Image(
            nsImage: MenuBarImage.render(
                health: model.center.health, segments: segments, style: model.preferences.menuBarStyle,
                trend: trend(segments))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(segments))
        // A click on a notification asks for the dashboard from outside the views.
        .onChange(of: model.dashboardRequest) { openDashboard(using: openWindow) }
    }

    /// The values to show next to the icon: none while the server cannot be
    /// read, and, if the user chose so, none while everything is fine.
    private var segments: [MenuBarSegment] {
        let preferences = model.preferences
        guard !preferences.menuBarItems.isEmpty, let monitor = model.menuBarMonitor, monitor.health != .offline
        else { return [] }
        if preferences.menuBarVisibility == .onlyOnProblems, model.center.health < .warning { return [] }
        return MenuBarText.segments(preferences.menuBarItems, from: monitor.snapshot)
    }

    /// The trend of the first value, if the user wants one.
    private func trend(_ segments: [MenuBarSegment]) -> TrendLine? {
        guard model.preferences.menuBarTrend, let first = segments.first else { return nil }
        return TrendLine(values: model.menuBarSampler.history(for: first.metric), range: first.metric.fixedRange)
    }

    private func accessibilityText(_ segments: [MenuBarSegment]) -> String {
        let status = String(localized: "MetriBar, \(model.center.health.label)")
        let values = segments.map { "\($0.metric.title) \($0.text)" }
        return ([status] + values).joined(separator: ", ")
    }
}
