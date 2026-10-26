import MetriBarKit
import SwiftUI

struct NetworkSensorsView: View {
    let monitor: ServerMonitor

    @State private var interfaceOrder = [KeyPathComparator(\InterfaceRow.received, order: .reverse)]

    var body: some View {
        if monitor.snapshot.network == nil {
            FeedPlaceholder(monitor: monitor, feed: .network)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashboardGroup(title: String(localized: "Network Interfaces")) {
                        Table(interfaces.sorted(using: interfaceOrder), sortOrder: $interfaceOrder) {
                            TableColumn("Interface", value: \.name) { row in
                                Label {
                                    Text(row.name)
                                } icon: {
                                    Image(systemName: row.isUp ? "circle.fill" : "circle")
                                        .foregroundStyle(row.isUp ? .green : .secondary)
                                        .imageScale(.small)
                                }
                            }
                            TableColumn("Received", value: \.received) {
                                NumberCell(text: Format.bytesPerSecond($0.received))
                            }
                            TableColumn("Sent", value: \.sent) { NumberCell(text: Format.bytesPerSecond($0.sent)) }
                            TableColumn("Total Received", value: \.totalReceived) {
                                NumberCell(text: Format.bytes($0.totalReceived))
                            }
                            TableColumn("Total Sent", value: \.totalSent) {
                                NumberCell(text: Format.bytes($0.totalSent))
                            }
                            TableColumn("Link", value: \.linkSpeed) {
                                NumberCell(
                                    text: $0.linkSpeed > 0 ? Format.bytesPerSecond($0.linkSpeed) : Format.placeholder)
                            }
                        }
                        .frame(minHeight: 160)
                    }
                    sensorsGroup
                    gpuGroup
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private var sensorsGroup: some View {
        let sensors = monitor.snapshot.sensors?.items ?? []
        DashboardGroup(title: String(localized: "Sensors")) {
            if !monitor.snapshot.plugins.contains("sensors") {
                Text("The sensors plugin is not active on this server.").foregroundStyle(.secondary)
            } else if sensors.isEmpty {
                Text("No sensors reported.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(Array(sensors.enumerated()), id: \.offset) { _, sensor in
                        GridRow {
                            Image(systemName: symbol(for: sensor.kind))
                                .foregroundStyle(color(for: sensor))
                            Text(sensor.label ?? "–")
                            Text(value(for: sensor))
                                .monospacedDigit()
                                .foregroundStyle(color(for: sensor))
                                .gridColumnAlignment(.trailing)
                            Text(limits(for: sensor))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var gpuGroup: some View {
        if let gpus = monitor.snapshot.gpus?.items, !gpus.isEmpty {
            DashboardGroup(title: String(localized: "GPU")) {
                ForEach(Array(gpus.enumerated()), id: \.offset) { _, gpu in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gpu.name ?? gpu.gpuId ?? "GPU").font(.subheadline.weight(.semibold))
                        MeterRow(title: String(localized: "Load"), percent: gpu.proc, level: .unknown)
                        MeterRow(title: String(localized: "Memory"), percent: gpu.mem, level: .unknown)
                        if let temperature = gpu.temperature {
                            Text(Format.temperature(temperature, unit: "C")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var interfaces: [InterfaceRow] {
        (monitor.snapshot.network?.items ?? []).compactMap { item in
            guard let name = item.interfaceName, item.hidden != true else { return nil }
            return InterfaceRow(
                id: name, name: name, isUp: item.isUp ?? false, received: item.bytesRecv ?? 0,
                sent: item.bytesSent ?? 0, totalReceived: item.bytesRecvCumul ?? 0,
                totalSent: item.bytesSentCumul ?? 0, linkSpeed: item.linkSpeed ?? 0)
        }
    }

    private func symbol(for kind: Sensor.Kind) -> String {
        switch kind {
        case .temperature: "thermometer.medium"
        case .fan: "fan"
        case .battery: "battery.75percent"
        case .other: "sensor"
        }
    }

    private func value(for sensor: Sensor) -> String {
        switch sensor.kind {
        case .temperature: Format.temperature(sensor.value, unit: sensor.unit)
        case .fan: String(localized: "\(Format.number(sensor.value)) rpm")
        case .battery: Format.percent(sensor.value)
        case .other: "\(Format.number(sensor.value, fractionDigits: 1)) \(sensor.unit ?? "")"
        }
    }

    private func limits(for sensor: Sensor) -> String {
        guard sensor.kind == .temperature else { return "" }
        let parts = [
            sensor.warning.map { String(localized: "warning \(Format.temperature($0, unit: sensor.unit))") },
            sensor.critical.map { String(localized: "critical \(Format.temperature($0, unit: sensor.unit))") },
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func color(for sensor: Sensor) -> Color {
        guard let value = sensor.value, sensor.kind == .temperature else { return .primary }
        if let critical = sensor.critical, value >= critical { return .red }
        if let warning = sensor.warning, value >= warning { return .orange }
        return .primary
    }
}

/// Plain data for the table; `nonisolated` so its key paths are `Sendable`
/// for `KeyPathComparator` despite the app's `MainActor` default isolation.
nonisolated struct InterfaceRow: Identifiable, Sendable {
    let id: String
    let name: String
    let isUp: Bool
    let received: Double
    let sent: Double
    let totalReceived: Double
    let totalSent: Double
    let linkSpeed: Double
}
