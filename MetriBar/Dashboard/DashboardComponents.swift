import MetriBarKit
import SwiftUI

/// A rounded card with title, optional accessory text and trailing
/// controls. With `showAll`, the title opens that section.
///
/// Cards are content, so they get a plain fill and no Liquid Glass; glass
/// belongs to the toolbar, sidebar and other controls floating above.
struct DashboardCard<Trailing: View, Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    let title: String
    let systemImage: String
    var accessory: String?
    /// Section opened by clicking the title.
    var showAll: DashboardSection?
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleView
                if let accessory {
                    Text(accessory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                trailing
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: shape)
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(.separator)
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if let showAll {
            Button {
                model.dashboardSection = showAll
            } label: {
                HStack(spacing: 4) {
                    Label(title, systemImage: systemImage)
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.headline)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Show \(showAll.title)"))
        } else {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }
}

extension DashboardCard where Trailing == EmptyView {
    init(
        title: String, systemImage: String, accessory: String? = nil, showAll: DashboardSection? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title, systemImage: systemImage, accessory: accessory, showAll: showAll, trailing: { EmptyView() },
            content: content)
    }
}

/// Cards in rows of equal height. The number of columns follows the
/// available width, so a short card never leaves a gap below it.
struct CardGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    var minimumWidth: CGFloat = 320
    var spacing: CGFloat = 16
    @ViewBuilder let card: (Item) -> Card

    @State private var columns = 2

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(row) { item in
                        card(item)
                    }
                    // Keep the width of the cards in an incomplete last row.
                    ForEach(row.count..<columns, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
                // Every card takes the height of the tallest one in its row.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(ColumnCount(minimumWidth: minimumWidth, spacing: spacing, columns: $columns))
    }

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
    }
}

/// Measures how many columns of at least `minimumWidth` fit. Not generic,
/// so the geometry closure captures no generic metatypes.
private struct ColumnCount: ViewModifier {
    let minimumWidth: CGFloat
    let spacing: CGFloat
    @Binding var columns: Int

    func body(content: Content) -> some View {
        content.onGeometryChange(for: Int.self) { [minimumWidth, spacing] proxy in
            max(1, Int((proxy.size.width + spacing) / (minimumWidth + spacing)))
        } action: {
            columns = $0
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

/// Bar and percentage in a table cell, colored by level.
struct PercentCell: View {
    let percent: Double?
    var level: Level = .unknown

    var body: some View {
        HStack(spacing: 6) {
            UsageBar(fraction: (percent ?? 0) / 100, color: level.color)
                .frame(minWidth: 40)
            Text(Format.percent(percent))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Format.percent(percent))
    }
}
