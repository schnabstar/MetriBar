import MetriBarKit
import SwiftUI

struct ContainersView: View {
    let monitor: ServerMonitor

    @State private var sortOrder = [KeyPathComparator(\ContainerTableRow.cpu, order: .reverse)]
    @State private var search = ""
    @State private var runningOnly = false

    var body: some View {
        if !monitor.snapshot.plugins.isEmpty, !monitor.snapshot.plugins.contains("containers") {
            ContentUnavailableView(
                "Containers Plugin Not Active", systemImage: "shippingbox",
                description: Text("Glances on this server does not publish container data."))
        } else if monitor.snapshot.containers == nil {
            FeedPlaceholder(monitor: monitor, feed: .containers)
        } else if monitor.snapshot.containers?.items.isEmpty == true {
            ContentUnavailableView(
                "No Containers", systemImage: "shippingbox",
                description: Text("Glances reports no containers. Does it have access to the Docker or Podman socket?"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Running only", isOn: $runningOnly)
                        .toggleStyle(.checkbox)
                }
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { row in
                        Label {
                            Text(row.name)
                        } icon: {
                            Image(systemName: row.symbol).foregroundStyle(row.color).imageScale(.small)
                        }
                    }
                    TableColumn("Status", value: \.status).width(min: 60, ideal: 80)
                    TableColumn("Image", value: \.image)
                    TableColumn("CPU", value: \.cpu) { row in
                        NumberCell(text: row.cpuText)
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Memory", value: \.memory) { row in
                        NumberCell(text: row.memoryText)
                    }
                    .width(min: 90, ideal: 130)
                    TableColumn("Network", value: \.network) { row in
                        NumberCell(
                            text: "↓ \(Format.bitsPerSecond(row.networkRx)) ↑ \(Format.bitsPerSecond(row.networkTx))")
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn("Disk I/O", value: \.io) { row in
                        NumberCell(
                            text: "R \(Format.bytesPerSecond(row.ioRead)) W \(Format.bytesPerSecond(row.ioWrite))")
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn("Up", value: \.started) { row in
                        NumberCell(text: row.uptimeText)
                    }
                    .width(min: 60, ideal: 70)
                    TableColumn("Ports", value: \.ports)
                }
            }
            .padding()
            .searchable(text: $search, prompt: Text("Name or image"))
        }
    }

    private var summary: String {
        let items = monitor.snapshot.containers?.items ?? []
        let engines = Set(items.compactMap(\.engine)).sorted().joined(separator: ", ")
        let running = items.filter(\.isRunning).count
        return String(localized: "\(running) of \(items.count) running") + (engines.isEmpty ? "" : " · \(engines)")
    }

    private var rows: [ContainerTableRow] {
        let now = Date.now
        let all = (monitor.snapshot.containers?.items ?? []).compactMap { ContainerTableRow($0, now: now) }
        return all.filter { row in
            (!runningOnly || row.isRunning)
                && (search.isEmpty || row.name.localizedCaseInsensitiveContains(search)
                    || row.image.localizedCaseInsensitiveContains(search))
        }
        .sorted(using: sortOrder)
    }
}

/// Plain data for the table; `nonisolated` so its key paths are `Sendable`
/// for `KeyPathComparator` despite the app's `MainActor` default isolation.
nonisolated struct ContainerTableRow: Identifiable, Sendable {
    let id: String
    let name: String
    let status: String
    let image: String
    let isRunning: Bool
    let isUnhealthy: Bool
    let cpu: Double
    let cpuLimit: Double?
    let memory: Double
    let memoryLimit: Double?
    let networkRx: Double
    let networkTx: Double
    let ioRead: Double
    let ioWrite: Double
    /// Seconds since start, 0 when not running; sorts by uptime.
    let started: Double
    let ports: String

    init?(_ container: ContainerInfo, now: Date) {
        guard let name = container.name else { return nil }
        id = container.id ?? name
        self.name = name
        status = container.status ?? ""
        image = container.imageName ?? ""
        isRunning = container.isRunning
        isUnhealthy = container.isUnhealthy
        cpu = container.cpuPercent ?? 0
        cpuLimit = container.cpuLimit
        memory = container.memoryUsage ?? 0
        memoryLimit = container.memoryLimit
        networkRx = container.networkRx ?? 0
        networkTx = container.networkTx ?? 0
        ioRead = container.ioRx ?? 0
        ioWrite = container.ioWx ?? 0
        started = container.startDate.map { now.timeIntervalSince($0) } ?? 0
        ports = container.ports?.values.joined(separator: ", ") ?? ""
    }

    var network: Double { networkRx + networkTx }
    var io: Double { ioRead + ioWrite }

    var cpuText: String {
        guard isRunning else { return Format.placeholder }
        guard let cpuLimit, cpuLimit > 0 else { return Format.percent(cpu) }
        return String(localized: "\(Format.percent(cpu)) of \(Format.number(cpuLimit, fractionDigits: 1)) CPU")
    }

    var memoryText: String {
        guard isRunning else { return Format.placeholder }
        guard let memoryLimit, memoryLimit > 0 else { return Format.bytes(memory) }
        return "\(Format.bytes(memory)) / \(Format.bytes(memoryLimit))"
    }

    var uptimeText: String {
        isRunning && started > 0 ? Format.duration(.seconds(started)) : Format.placeholder
    }

    var symbol: String {
        if isUnhealthy { return "exclamationmark.triangle.fill" }
        return isRunning ? "circle.fill" : "circle"
    }

    var color: Color {
        if isUnhealthy { return .orange }
        return isRunning ? .green : .secondary
    }
}
