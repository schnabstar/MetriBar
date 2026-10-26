import MetriBarKit
import SwiftUI

/// A metric tile of the overview: title, large value, optional bar and details.
struct StatTile: View {
    let title: String
    let systemImage: String
    let value: String
    var percent: Double?
    var level: Level = .unknown
    var details: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(level >= .warning ? level.color : .primary)
            if let percent {
                ProgressView(value: min(max(percent / 100, 0), 1))
                    .tint(level.color)
                    .accessibilityHidden(true)
            }
            ForEach(details, id: \.self) { detail in
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(([value] + details).joined(separator: ", "))
    }
}

/// A titled group in a dashboard section.
struct DashboardGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

/// Placeholder while a feed has not delivered data yet, or when the
/// server does not publish it.
struct FeedPlaceholder: View {
    let monitor: ServerMonitor
    let feed: Feed
    var unavailable: String?

    var body: some View {
        if let error = monitor.feedErrors[feed] {
            ContentUnavailableView(
                ConnectionProblem(error).title, systemImage: "exclamationmark.triangle",
                description: Text(ConnectionProblem(error).advice(hasCredentials: monitor.config.username != nil)))
        } else if let unavailable {
            ContentUnavailableView(unavailable, systemImage: "questionmark.circle")
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Header cell content for sortable tables, right-aligned numbers.
struct NumberCell: View {
    let text: String

    var body: some View {
        Text(text)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Bar and percentage in a table cell, colored by level.
struct PercentCell: View {
    let percent: Double?
    var level: Level = .unknown

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: min(max((percent ?? 0) / 100, 0), 1))
                .tint(level.color)
                .frame(minWidth: 40)
            Text(Format.percent(percent))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Format.percent(percent))
    }
}
