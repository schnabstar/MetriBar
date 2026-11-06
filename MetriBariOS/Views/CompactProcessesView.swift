import MetriBarKit
import SwiftUI

struct CompactProcessesView: View {
    let monitor: ServerMonitor

    @State private var search = ""
    @State private var sortMetric: SortMetric = .cpu
    @State private var selectedProcess: SelectedProcess?

    enum SortMetric: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"
        case name = "Name"
        case pid = "PID"

        var id: Self { self }
    }

    var body: some View {
        if monitor.snapshot.processes == nil {
            FeedPlaceholder(monitor: monitor, feed: .processes)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("Sort by", selection: $sortMetric) {
                            ForEach(SortMetric.allCases) { metric in
                                Label(metric.rawValue, systemImage: sortIcon(for: metric)).tag(metric)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Sort: \(sortMetric.rawValue)")
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.fill.tertiary, in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    ForEach(Array(filteredProcesses.enumerated()), id: \.offset) { item in
                        let process = item.element
                        Button {
                            selectedProcess = SelectedProcess(process: process)
                        } label: {
                            ProcessListRow(process: process)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Show Details", systemImage: "info.circle") {
                                selectedProcess = SelectedProcess(process: process)
                            }
                            Divider()
                            if let name = process.name {
                                Button("Copy Name", systemImage: "doc.on.doc") { Clipboard.copy(name) }
                            }
                            if let pid = process.pid {
                                Button("Copy PID", systemImage: "number") { Clipboard.copy(String(pid)) }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $search, prompt: Text("Search name or user"))
            }
            .sheet(item: $selectedProcess) { process in
                ProcessInspectorSheet(process: process.process)
            }
        }
    }

    private var summaryText: String {
        let count = monitor.snapshot.processes?.count ?? 0
        let total = monitor.snapshot.processCount?.total ?? count
        return "Showing \(count) of \(total) processes"
    }

    private var filteredProcesses: [ProcessEntry] {
        let all = monitor.snapshot.processes ?? []
        let filtered = search.isEmpty ? all : all.filter {
            ($0.name?.localizedCaseInsensitiveContains(search) ?? false) ||
            ($0.username?.localizedCaseInsensitiveContains(search) ?? false)
        }
        return filtered.sorted { p1, p2 in
            switch sortMetric {
            case .cpu:
                return (p1.cpuPercent ?? 0) > (p2.cpuPercent ?? 0)
            case .memory:
                return (p1.memoryPercent ?? 0) > (p2.memoryPercent ?? 0)
            case .name:
                return (p1.name ?? "").localizedCaseInsensitiveCompare(p2.name ?? "") == .orderedAscending
            case .pid:
                return (p1.pid ?? 0) < (p2.pid ?? 0)
            }
        }
    }

    private func sortIcon(for metric: SortMetric) -> String {
        switch metric {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .name: "textformat"
        case .pid: "number"
        }
    }
}

private struct ProcessListRow: View {
    let process: ProcessEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(process.name ?? "–")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("PID \(process.pid.map(String.init) ?? "–")")
                    Text("•")
                    Text(process.username ?? "–")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                // CPU badge
                let cpu = process.cpuPercent ?? 0
                Text(Format.percent(cpu))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(cpuBadgeColor(cpu).opacity(0.15), in: Capsule())
                    .foregroundStyle(cpuBadgeColor(cpu))

                Text(Format.bytes(process.memoryInfo?.rss))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func cpuBadgeColor(_ cpu: Double) -> Color {
        if cpu >= 70 { return .red }
        if cpu >= 30 { return .orange }
        return .primary
    }
}

private struct SelectedProcess: Identifiable {
    let id = UUID()
    let process: ProcessEntry
}
