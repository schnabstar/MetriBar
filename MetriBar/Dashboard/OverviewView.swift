import Charts
import MetriBarKit
import SwiftUI

struct OverviewView: View {
    let monitor: ServerMonitor

    var body: some View {
        ScrollView {
            OverviewContent(monitor: monitor)
        }
    }
}

/// The overview without its scroll view, so the snapshot tool can render it.
struct OverviewContent: View {
    @Environment(AppModel.self) private var model
    let monitor: ServerMonitor

    private var snapshot: ServerSnapshot { monitor.snapshot }

    private enum Card: Identifiable {
        case trend, network, sensors, storage, containers, system, alerts
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            gauges
            CardGrid(items: cards) { card in
                switch card {
                case .trend: trendCard
                case .network: networkCard
                case .sensors: sensorsCard
                case .storage: storageCard
                case .containers: containersCard
                case .system: systemCard
                case .alerts: alertsCard
                }
            }
        }
        .padding()
    }

    private var cards: [Card] {
        [
            .trend, .network, snapshot.plugins.contains("sensors") ? .sensors : nil, .storage,
            snapshot.plugins.contains("containers") ? .containers : nil, .system, .alerts,
        ].compactMap { $0 }
    }

    // MARK: Gauges

    private var gauges: some View {
        let cpu = snapshot.cpu
        let memory = snapshot.memory
        let swap = snapshot.swap
        let load = snapshot.load
        let cores = Double(load?.value.cpucore ?? cpu?.value.cpucore ?? 0)
        return DashboardCard(title: String(localized: "Utilization"), systemImage: "gauge.with.dots.needle.67percent") {
            HStack(alignment: .top, spacing: 12) {
                RingGauge(
                    title: String(localized: "CPU"), percent: cpu?.value.total, level: cpu?.level("total") ?? .unknown,
                    value: Format.percent(cpu?.value.total),
                    detail: String(
                        localized:
                            "User \(Format.percent(cpu?.value.user)) · System \(Format.percent(cpu?.value.system))"))
                RingGauge(
                    title: String(localized: "Memory"), percent: memory?.value.percent,
                    level: memory?.level("percent") ?? .unknown, value: Format.percent(memory?.value.percent),
                    detail: "\(Format.bytes(memory?.value.used)) / \(Format.bytes(memory?.value.total))")
                RingGauge(
                    title: String(localized: "Swap"), percent: swap?.value.percent,
                    level: swap?.level("percent") ?? .unknown, value: Format.percent(swap?.value.percent),
                    detail: "\(Format.bytes(swap?.value.used)) / \(Format.bytes(swap?.value.total))")
                RingGauge(
                    title: String(localized: "Load"),
                    percent: cores > 0 ? load?.value.min1.map { $0 / cores * 100 } : nil,
                    level: load?.worstLevel ?? .unknown, value: Format.load(load?.value.min1),
                    detail: String(
                        localized: "5 min \(Format.load(load?.value.min5)) · 15 min \(Format.load(load?.value.min15))"))
            }
        }
    }

    // MARK: Cards

    private var trendCard: some View {
        let history = snapshot.history
        let total = Self.sum(history.cpu, fields: ["user", "system"])
        let memory = history.memory?.points("percent") ?? []
        return DashboardCard(
            title: String(localized: "Trend"), systemImage: "chart.xyaxis.line",
            accessory: timeRange(history.cpu), showAll: .history
        ) {
            if total.isEmpty, memory.isEmpty {
                placeholder(feed: .history)
            } else {
                Sparkline(
                    series: [
                        .init(name: String(localized: "CPU"), points: total, color: .blue),
                        .init(name: String(localized: "Memory"), points: memory, color: .purple),
                    ], unit: .percent)
            }
        }
    }

    private var networkCard: some View {
        let interface = mainInterface
        let network = snapshot.history.network
        return DashboardCard(
            title: interface.map { String(localized: "Network \($0.interfaceName ?? "")") }
                ?? String(localized: "Network"),
            systemImage: "network", showAll: .network
        ) {
            if let interface {
                HStack(spacing: 24) {
                    rate(String(localized: "Received"), interface.bytesRecv, systemImage: "arrow.down", color: .blue)
                    rate(String(localized: "Sent"), interface.bytesSent, systemImage: "arrow.up", color: .green)
                }
                if let network, let name = interface.interfaceName {
                    Sparkline(
                        series: [
                            .init(
                                name: String(localized: "Received"), points: network.points("bytes_recv", item: name),
                                color: .blue),
                            .init(
                                name: String(localized: "Sent"), points: network.points("bytes_sent", item: name),
                                color: .green),
                        ], unit: .bytesPerSecond)
                }
                Text(
                    "Total \(Format.bytes(interface.bytesRecvCumul)) received · \(Format.bytes(interface.bytesSentCumul)) sent"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                placeholder(feed: .network)
            }
        }
    }

    private var sensorsCard: some View {
        let sensors = snapshot.sensors?.items ?? []
        return DashboardCard(
            title: String(localized: "Sensors"), systemImage: "thermometer.medium",
            showAll: .sensors
        ) {
            if snapshot.sensors == nil {
                placeholder(feed: .sensors)
            } else if sensors.isEmpty {
                Text("No sensors reported.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(sensors.enumerated()), id: \.offset) { _, sensor in
                        SensorRow(sensor: sensor)
                    }
                }
            }
        }
    }

    private var storageCard: some View {
        let fileSystems = uniqueFileSystems
        return DashboardCard(
            title: String(localized: "Storage"), systemImage: "internaldrive",
            showAll: .storage
        ) {
            if snapshot.fileSystems == nil {
                placeholder(feed: .storage)
            } else if fileSystems.isEmpty {
                Text("No file systems reported.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(fileSystems.prefix(4).enumerated()), id: \.offset) { _, fileSystem in
                        FileSystemSummary(
                            fileSystem: fileSystem,
                            level: snapshot.fileSystems?.level("percent", item: fileSystem.mntPoint ?? "") ?? .unknown)
                    }
                }
            }
        }
    }

    private var containersCard: some View {
        let containers = snapshot.containers?.items ?? []
        let running = containers.filter(\.isRunning)
        let unhealthy = containers.filter(\.isUnhealthy).count
        let stopped = containers.count - running.count
        let busiest = running.sorted { ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0) }
        return DashboardCard(
            title: String(localized: "Containers"), systemImage: "shippingbox",
            showAll: .containers
        ) {
            if snapshot.containers == nil {
                placeholder(feed: .containers)
            } else if containers.isEmpty {
                Text("No containers found. Does Glances have access to the Docker socket?")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    CountPill(count: running.count, label: String(localized: "running"), color: .green)
                    if unhealthy > 0 {
                        CountPill(count: unhealthy, label: String(localized: "unhealthy"), color: .orange)
                    }
                    if stopped > 0 {
                        CountPill(count: stopped, label: String(localized: "stopped"), color: .secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(busiest.prefix(5).enumerated()), id: \.offset) { _, container in
                        ContainerLoadRow(container: container)
                    }
                }
            }
        }
    }

    private var systemCard: some View {
        let system = snapshot.system
        let quickLook = snapshot.quickLook?.value
        let count = snapshot.processCount
        let processor = [
            quickLook?.cpuName,
            quickLook?.cpuLogCore.map { String(localized: "\($0) cores") },
            quickLook?.cpuHzCurrent.map {
                String(localized: "\(Format.number($0 / 1_000_000_000, fractionDigits: 1)) GHz")
            },
        ].compactMap { $0 }.joined(separator: " · ")
        let processes = count.map {
            String(localized: "\($0.total ?? 0) · \($0.running ?? 0) running · \($0.thread ?? 0) threads")
        }
        return DashboardCard(title: String(localized: "System"), systemImage: "desktopcomputer") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                InfoRow(title: String(localized: "Host name"), value: system?.hostname)
                InfoRow(title: String(localized: "Operating system"), value: system?.hrName)
                InfoRow(title: String(localized: "Processor"), value: processor.isEmpty ? nil : processor)
                InfoRow(title: String(localized: "Uptime"), value: Format.duration(snapshot.uptime?.duration))
                InfoRow(title: String(localized: "Processes"), value: processes)
                InfoRow(title: String(localized: "Glances"), value: snapshot.status?.glancesVersion)
            }
        }
    }

    private var alertsCard: some View {
        let ongoing = (snapshot.incidents?.incidents ?? []).filter { $0.ongoing == true }
        return DashboardCard(
            title: String(localized: "Active Alerts"), systemImage: "bell",
            showAll: .alerts
        ) {
            if ongoing.isEmpty {
                Label {
                    Text("No active alerts").foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } else {
                ForEach(Array(ongoing.enumerated()), id: \.offset) { _, incident in
                    IncidentRow(incident: incident)
                }
            }
        }
    }

    // MARK: Helpers

    private func rate(_ title: String, _ value: Double?, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(color)
            Text(Format.bytesPerSecond(value))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .numericTransition(value)
        }
    }

    private func placeholder(feed: Feed) -> some View {
        Group {
            if let error = monitor.feedErrors[feed] {
                Text(ConnectionProblem(error).title).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    private func timeRange(_ history: History?) -> String? {
        guard let timestamps = history?.timestamps, let first = timestamps.first, let last = timestamps.last,
            last > first
        else { return nil }
        return String(localized: "last \(Format.duration(.seconds(last - first)))")
    }

    /// The interface with the most traffic, ignoring loopback and hidden ones.
    private var mainInterface: NetworkInterface? {
        (snapshot.network?.items ?? [])
            .filter { $0.hidden != true && $0.interfaceName != "lo" && $0.isUp != false }
            .max {
                ($0.bytesRecvCumul ?? 0) + ($0.bytesSentCumul ?? 0) < ($1.bytesRecvCumul ?? 0)
                    + ($1.bytesSentCumul ?? 0)
            }
    }

    /// File systems by usage, one entry per device: Glances in a container
    /// reports every bind mount of the same disk.
    private var uniqueFileSystems: [FileSystem] {
        var seen = Set<String>()
        return (snapshot.fileSystems?.items ?? [])
            .sorted { ($0.percent ?? 0) > ($1.percent ?? 0) }
            .filter { fileSystem in
                let key = "\(fileSystem.deviceName ?? fileSystem.mntPoint ?? "")|\(fileSystem.size ?? 0)"
                return seen.insert(key).inserted
            }
    }

    /// Sum of several series of the same history, point by point.
    static func sum(_ history: History?, fields: [String]) -> [History.Point] {
        guard let history else { return [] }
        let columns = fields.compactMap { history.series[$0] }
        guard !columns.isEmpty else { return [] }
        return history.timestamps.enumerated().compactMap { index, timestamp in
            let values = columns.compactMap { index < $0.count ? $0[index] : nil }
            guard values.count == columns.count else { return nil }
            return History.Point(date: Date(timeIntervalSince1970: timestamp), value: values.reduce(0, +))
        }
    }
}

/// A small chart without time axis for trends.
struct Sparkline: View {
    struct Series {
        let name: String
        let points: [History.Point]
        let color: Color
    }

    let series: [Series]
    let unit: HistoryChart.Unit

    var body: some View {
        Chart {
            ForEach(series, id: \.name) { series in
                ForEach(series.points, id: \.date) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value))
                        .foregroundStyle(by: .value("Series", series.name))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel { Text(format(value.as(Double.self))).font(.caption2) }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 110)
    }

    private var domain: ClosedRange<Double> {
        if unit == .percent { return 0...100 }
        let maximum = series.flatMap(\.points).map(\.value).filter(\.isFinite).max() ?? 0
        return 0...max(maximum * 1.15, 1024)
    }

    private func format(_ value: Double?) -> String {
        switch unit {
        case .percent: Format.percent(value)
        case .number: Format.load(value)
        case .bytesPerSecond: Format.bytesPerSecond(value)
        }
    }
}

/// One temperature, fan or battery reading with a bar towards its limit.
struct SensorRow: View {
    let sensor: Sensor
    /// Shows the warning and critical temperature below the bar.
    var showsLimits = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: Self.symbol(for: sensor.kind))
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(sensor.label ?? "–").lineLimit(1)
                    Spacer()
                    Text(value)
                        .monospacedDigit()
                        .fontWeight(.medium)
                        .numericTransition(sensor.value)
                }
                if let fraction {
                    UsageBar(fraction: fraction, color: color, height: 4)
                }
                if showsLimits, let limits {
                    Text(limits)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func symbol(for kind: Sensor.Kind) -> String {
        switch kind {
        case .temperature: "thermometer.medium"
        case .fan: "fan"
        case .battery: "battery.75percent"
        case .other: "sensor"
        }
    }

    private var value: String {
        switch sensor.kind {
        case .temperature: Format.temperature(sensor.value, unit: sensor.unit)
        case .fan: String(localized: "\(Format.number(sensor.value)) rpm")
        case .battery: Format.percent(sensor.value)
        case .other: "\(Format.number(sensor.value, fractionDigits: 1)) \(sensor.unit ?? "")"
        }
    }

    /// Temperature relative to the critical limit, battery charge.
    private var fraction: Double? {
        guard let value = sensor.value else { return nil }
        switch sensor.kind {
        case .temperature: return value / (sensor.critical ?? 100)
        case .battery: return value / 100
        default: return nil
        }
    }

    private var limits: String? {
        guard sensor.kind == .temperature else { return nil }
        let parts = [
            sensor.warning.map { String(localized: "warning \(Format.temperature($0, unit: sensor.unit))") },
            sensor.critical.map { String(localized: "critical \(Format.temperature($0, unit: sensor.unit))") },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var color: Color {
        guard sensor.kind == .temperature, let value = sensor.value else { return .secondary }
        if let critical = sensor.critical, value >= critical { return .red }
        if let warning = sensor.warning, value >= warning { return .orange }
        return .teal
    }
}

private struct FileSystemSummary: View {
    let fileSystem: FileSystem
    let level: Level

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fileSystem.mntPoint ?? "–")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(Format.percent(fileSystem.percent))
                    .monospacedDigit()
                    .foregroundStyle(level >= .warning ? level.color : .primary)
            }
            UsageBar(fraction: (fileSystem.percent ?? 0) / 100, color: level.color)
            Text(
                "\(Format.bytes(fileSystem.used)) of \(Format.bytes(fileSystem.size)) · \(fileSystem.deviceName ?? "")"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ContainerLoadRow: View {
    let container: ContainerInfo

    var body: some View {
        HStack(spacing: 8) {
            Text(container.name ?? "–")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            UsageBar(fraction: (container.cpuPercent ?? 0) / 100, color: .blue)
                .frame(width: 60)
            Text(Format.percent(container.cpuPercent))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            Text(Format.bytes(container.memoryUsage))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String?

    var body: some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value ?? Format.placeholder)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

struct CountPill: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count) \(label)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}
