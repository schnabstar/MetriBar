import MetriBarKit
import SwiftUI

/// Sensors grouped by kind, and GPUs, as cards.
struct SensorsView: View {
    let monitor: ServerMonitor

    private enum Card: Identifiable, Hashable {
        case sensors(Sensor.Kind)
        case gpu(Int)
        var id: Self { self }
    }

    var body: some View {
        let snapshot = monitor.snapshot
        if !snapshot.plugins.isEmpty, !snapshot.plugins.contains("sensors"), gpus.isEmpty {
            ContentUnavailableView(
                "Sensors Plugin Not Active", systemImage: "thermometer.medium",
                description: Text("Glances on this server does not publish sensor data."))
        } else if snapshot.sensors == nil {
            FeedPlaceholder(monitor: monitor, feed: .sensors)
        } else if cards.isEmpty {
            ContentUnavailableView(
                "No Sensors", systemImage: "thermometer.medium",
                description: Text("Glances reports no sensors on this server."))
        } else {
            ScrollView {
                CardGrid(items: cards) { card in
                    switch card {
                    case .sensors(let kind): sensorCard(kind)
                    case .gpu(let index): gpuCard(gpus[index])
                    }
                }
                .padding()
            }
        }
    }

    private var sensors: [Sensor] { monitor.snapshot.sensors?.items ?? [] }
    private var gpus: [GPU] { monitor.snapshot.gpus?.items ?? [] }

    private var cards: [Card] {
        let kinds: [Sensor.Kind] = [.temperature, .fan, .battery, .other]
        return kinds.filter { kind in sensors.contains { $0.kind == kind } }.map(Card.sensors)
            + gpus.indices.map(Card.gpu)
    }

    private func sensorCard(_ kind: Sensor.Kind) -> some View {
        DashboardCard(title: title(for: kind), systemImage: SensorRow.symbol(for: kind)) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(sensors.filter { $0.kind == kind }.enumerated()), id: \.offset) { _, sensor in
                    SensorRow(sensor: sensor, showsLimits: true)
                }
            }
        }
    }

    private func gpuCard(_ gpu: GPU) -> some View {
        DashboardCard(title: gpu.name ?? gpu.gpuId ?? "GPU", systemImage: "cpu") {
            MeterGroup {
                MeterRow(title: String(localized: "Load"), percent: gpu.proc, level: .unknown)
                MeterRow(title: String(localized: "Memory"), percent: gpu.mem, level: .unknown)
                if let temperature = gpu.temperature {
                    HStack(spacing: 8) {
                        MeterLabel(title: String(localized: "Temperature"))
                        Text(Format.temperature(temperature, unit: "C")).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func title(for kind: Sensor.Kind) -> String {
        switch kind {
        case .temperature: String(localized: "Temperatures")
        case .fan: String(localized: "Fans")
        case .battery: String(localized: "Batteries")
        case .other: String(localized: "Other Sensors")
        }
    }
}
