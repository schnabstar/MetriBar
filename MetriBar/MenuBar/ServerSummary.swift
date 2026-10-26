import MetriBarKit
import SwiftUI

/// Problem banner, key metrics and containers of one server.
struct ServerSummary: View {
    let monitor: ServerMonitor
    let onShowSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let problem {
                ProblemBanner(problem: problem, monitor: monitor, onShowSettings: onShowSettings)
            }
            if monitor.snapshot.cpu != nil {
                Group {
                    MetricsSection(snapshot: monitor.snapshot)
                    ContainersSection(snapshot: monitor.snapshot)
                }
                .opacity(monitor.isStale ? 0.45 : 1)
                if monitor.isStale, let lastSuccess = monitor.lastSuccess {
                    Text("Showing values from \(Format.relative(lastSuccess)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if problem == nil {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("Connecting…").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 20)
            }
        }
        .padding(14)
    }

    /// Shown when the server is unusable, not for single failed attempts.
    private var problem: ConnectionProblem? {
        switch monitor.state {
        case .needsCredentials, .unsupportedVersion:
            ConnectionProblem(monitor.state)
        case .failed where monitor.health == .offline:
            ConnectionProblem(monitor.state)
        default:
            nil
        }
    }
}

struct MetricsSection: View {
    let snapshot: ServerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cpu = snapshot.cpu {
                MeterRow(title: String(localized: "CPU"), percent: cpu.value.total, level: cpu.level("total"))
            }
            if let memory = snapshot.memory {
                MeterRow(
                    title: String(localized: "Memory"), percent: memory.value.percent, level: memory.level("percent"),
                    detail: "\(Format.bytes(memory.value.used)) / \(Format.bytes(memory.value.total))")
            }
            if let load = snapshot.load?.value {
                HStack(spacing: 8) {
                    Text("Load").frame(width: 64, alignment: .leading)
                    Text([load.min1, load.min5, load.min15].map(Format.load).joined(separator: " · "))
                        .monospacedDigit()
                    Spacer()
                    if let cores = load.cpucore {
                        Text("\(cores) cores").foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let uptime = snapshot.uptime {
                HStack(spacing: 8) {
                    Text("Uptime").frame(width: 64, alignment: .leading)
                    Text(Format.duration(uptime.duration)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct ContainersSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let snapshot: ServerSnapshot
    private let limit = 6

    var body: some View {
        if let containers = snapshot.containers?.items {
            VStack(alignment: .leading, spacing: 6) {
                let running = containers.filter(\.isRunning).count
                Text("Containers \(running)/\(containers.count) running")
                    .font(.subheadline.weight(.semibold))
                if containers.isEmpty {
                    Text("No containers found. Does Glances have access to the Docker socket?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(sorted(containers).prefix(limit).enumerated()), id: \.offset) { _, container in
                        ContainerRow(container: container)
                    }
                    if containers.count > limit {
                        Button("and \(containers.count - limit) more in the dashboard") {
                            model.dashboardSection = .containers
                            openWindow(id: SceneID.dashboard)
                            NSApplication.shared.activate()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
        } else if snapshot.plugins.isEmpty == false, !snapshot.plugins.contains("containers") {
            Text("The containers plugin is not active on this server.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Unhealthy first, then running by CPU usage, then stopped.
    private func sorted(_ containers: [ContainerInfo]) -> [ContainerInfo] {
        containers.sorted { lhs, rhs in
            if lhs.isUnhealthy != rhs.isUnhealthy { return lhs.isUnhealthy }
            if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
            return (lhs.cpuPercent ?? 0) > (rhs.cpuPercent ?? 0)
        }
    }
}

struct ContainerRow: View {
    let container: ContainerInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(container.name ?? "–")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if container.isRunning {
                Text(Format.percent(container.cpuPercent))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                Text(Format.bytes(container.memoryUsage))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            } else {
                Text(container.status ?? "–").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(container.name ?? "")
        .accessibilityValue(accessibilityValue)
    }

    private var symbol: String {
        if container.isUnhealthy { return "exclamationmark.triangle.fill" }
        return container.isRunning ? "circle.fill" : "circle"
    }

    private var color: Color {
        if container.isUnhealthy { return .orange }
        return container.isRunning ? .green : .secondary
    }

    private var accessibilityValue: String {
        var parts = [container.status ?? ""]
        if container.isRunning {
            parts.append(String(localized: "CPU \(Format.percent(container.cpuPercent))"))
            parts.append(String(localized: "Memory \(Format.bytes(container.memoryUsage))"))
        }
        return parts.joined(separator: ", ")
    }
}
