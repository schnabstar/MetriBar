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
    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: columns, spacing: 12) {
                cpuTile
                memoryTile
                swapTile
                loadTile
                processesTile
                uptimeTile
            }
            if let cores = snapshot.quickLook?.value.percpu, !cores.isEmpty {
                coresGroup(cores)
            }
            incidentsGroup
            containersGroup
        }
        .padding()
    }

    // MARK: Tiles

    private var cpuTile: some View {
        let cpu = snapshot.cpu
        return StatTile(
            title: String(localized: "CPU"), systemImage: "cpu", value: Format.percent(cpu?.value.total),
            percent: cpu?.value.total, level: cpu?.level("total") ?? .unknown,
            details: [
                String(
                    localized:
                        "User \(Format.percent(cpu?.value.user)) · System \(Format.percent(cpu?.value.system)) · I/O \(Format.percent(cpu?.value.iowait))"
                )
            ])
    }

    private var memoryTile: some View {
        let memory = snapshot.memory
        return StatTile(
            title: String(localized: "Memory"), systemImage: "memorychip", value: Format.percent(memory?.value.percent),
            percent: memory?.value.percent, level: memory?.level("percent") ?? .unknown,
            details: [
                "\(Format.bytes(memory?.value.used)) / \(Format.bytes(memory?.value.total))",
                String(localized: "Available \(Format.bytes(memory?.value.available))"),
            ])
    }

    private var swapTile: some View {
        let swap = snapshot.swap
        return StatTile(
            title: String(localized: "Swap"), systemImage: "arrow.left.arrow.right",
            value: Format.percent(swap?.value.percent),
            percent: swap?.value.percent, level: swap?.level("percent") ?? .unknown,
            details: ["\(Format.bytes(swap?.value.used)) / \(Format.bytes(swap?.value.total))"])
    }

    private var loadTile: some View {
        let load = snapshot.load
        return StatTile(
            title: String(localized: "Load"), systemImage: "gauge.with.dots.needle.33percent",
            value: Format.load(load?.value.min1), level: load?.worstLevel ?? .unknown,
            details: [
                String(
                    localized:
                        "5 min \(Format.load(load?.value.min5)) · 15 min \(Format.load(load?.value.min15))"),
                load?.value.cpucore.map { String(localized: "\($0) cores") } ?? "",
            ].filter { !$0.isEmpty })
    }

    private var processesTile: some View {
        let count = snapshot.processCount
        return StatTile(
            title: String(localized: "Processes"), systemImage: "list.bullet.rectangle",
            value: count?.total.map(String.init) ?? Format.placeholder,
            details: [
                String(
                    localized:
                        "\(count?.running ?? 0) running · \(count?.sleeping ?? 0) sleeping · \(count?.thread ?? 0) threads"
                )
            ])
    }

    private var uptimeTile: some View {
        StatTile(
            title: String(localized: "Uptime"), systemImage: "clock",
            value: Format.duration(snapshot.uptime?.duration),
            details: [snapshot.system?.hostname, snapshot.system?.platform].compactMap { $0 })
    }

    // MARK: Groups

    private func coresGroup(_ cores: [QuickLook.Core]) -> some View {
        let quickLook = snapshot.quickLook?.value
        let title = [
            quickLook?.cpuName,
            quickLook?.cpuHzCurrent.map {
                String(localized: "\(Format.number($0 / 1_000_000_000, fractionDigits: 1)) GHz")
            },
        ].compactMap { $0 }.joined(separator: " · ")
        return DashboardGroup(title: title.isEmpty ? String(localized: "Cores") : title) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 8) {
                ForEach(Array(cores.enumerated()), id: \.offset) { index, core in
                    MeterRow(
                        title: String(localized: "Core \(core.cpuNumber ?? index)"), percent: core.total,
                        level: core.level ?? .unknown)
                }
            }
        }
    }

    @ViewBuilder
    private var incidentsGroup: some View {
        let ongoing = (snapshot.incidents?.incidents ?? []).filter { $0.ongoing == true }
        DashboardGroup(title: String(localized: "Active Alerts")) {
            if ongoing.isEmpty {
                Label("No active alerts", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(ongoing.enumerated()), id: \.offset) { _, incident in
                    IncidentRow(incident: incident)
                }
                Button("Show All Alerts") { model.dashboardSection = .alerts }
                    .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private var containersGroup: some View {
        if let containers = snapshot.containers?.items, !containers.isEmpty {
            DashboardGroup(title: String(localized: "Busiest Containers")) {
                let busiest = containers.filter(\.isRunning).sorted { ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0) }
                ForEach(Array(busiest.prefix(5).enumerated()), id: \.offset) { _, container in
                    ContainerRow(container: container)
                }
                Button("Show All Containers") { model.dashboardSection = .containers }
                    .buttonStyle(.link)
            }
        }
    }
}
