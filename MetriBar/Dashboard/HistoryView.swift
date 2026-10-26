import Charts
import MetriBarKit
import SwiftUI

struct HistoryView: View {
    let monitor: ServerMonitor

    var body: some View {
        if monitor.snapshot.history.cpu == nil {
            FeedPlaceholder(monitor: monitor, feed: .history)
        } else {
            ScrollView {
                HistoryContent(monitor: monitor)
            }
        }
    }
}

/// The charts without their scroll view, so the snapshot tool can render them.
struct HistoryContent: View {
    let monitor: ServerMonitor
    @State private var interface: String?

    private var history: HistorySet { monitor.snapshot.history }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let range = timeRange {
                Text("History kept by Glances: \(range)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HistoryChart(
                title: String(localized: "CPU"), unit: .percent,
                series: [
                    (String(localized: "User"), history.cpu?.points("user") ?? []),
                    (String(localized: "System"), history.cpu?.points("system") ?? []),
                ], stacked: true)
            HistoryChart(
                title: String(localized: "Memory"), unit: .percent,
                series: [(String(localized: "Used"), history.memory?.points("percent") ?? [])])
            HistoryChart(
                title: String(localized: "Load"), unit: .number,
                series: [
                    (String(localized: "1 min"), history.load?.points("min1") ?? []),
                    (String(localized: "5 min"), history.load?.points("min5") ?? []),
                    (String(localized: "15 min"), history.load?.points("min15") ?? []),
                ])
            networkChart
        }
        .padding()
    }

    @ViewBuilder
    private var networkChart: some View {
        if let network = history.network {
            let interfaces = network.items(for: "bytes_recv").filter { $0 != "lo" }
            let selected = interface.flatMap { interfaces.contains($0) ? $0 : nil } ?? interfaces.first
            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Interface", selection: Binding(get: { selected }, set: { interface = $0 })) {
                        ForEach(interfaces, id: \.self) { Text($0).tag($0) }
                    }
                    .fixedSize()
                    HistoryChart(
                        title: String(localized: "Network \(selected)"), unit: .bytesPerSecond,
                        series: [
                            (String(localized: "Received"), network.points("bytes_recv", item: selected)),
                            (String(localized: "Sent"), network.points("bytes_sent", item: selected)),
                        ])
                }
            }
        }
    }

    private var timeRange: String? {
        guard let timestamps = history.cpu?.timestamps, let first = timestamps.first, let last = timestamps.last,
            last > first
        else { return nil }
        return Format.duration(.seconds(last - first))
    }
}

/// A line or stacked area chart with hover read-out.
struct HistoryChart: View {
    enum Unit {
        case percent, number, bytesPerSecond
    }

    let title: String
    let unit: Unit
    let series: [(name: String, points: [History.Point])]
    var stacked = false

    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Chart {
                ForEach(series, id: \.name) { series in
                    ForEach(series.points, id: \.date) { point in
                        if stacked {
                            AreaMark(x: .value("Time", point.date), y: .value(title, point.value))
                                .foregroundStyle(by: .value("Series", series.name))
                        } else {
                            LineMark(x: .value("Time", point.date), y: .value(title, point.value))
                                .foregroundStyle(by: .value("Series", series.name))
                        }
                    }
                }
                if let selectedDate {
                    RuleMark(x: .value("Time", selectedDate))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            readout(at: selectedDate)
                        }
                }
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { Text(format(value.as(Double.self))) }
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 180)
        }
    }

    /// 0…100 for percentages, otherwise from zero to a bit above the maximum.
    private var yDomain: ClosedRange<Double> {
        if unit == .percent { return 0...100 }
        let maximum = series.flatMap(\.points).map(\.value).filter(\.isFinite).max() ?? 0
        return 0...max(maximum * 1.1, unit == .number ? 1 : 1024)
    }

    private func readout(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary)
            ForEach(series, id: \.name) { series in
                if let point = series.points.min(by: {
                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                }) {
                    Text("\(series.name): \(format(point.value))").font(.caption).monospacedDigit()
                }
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func format(_ value: Double?) -> String {
        switch unit {
        case .percent: Format.percent(value)
        case .number: Format.load(value)
        case .bytesPerSecond: Format.bytesPerSecond(value)
        }
    }
}
