import MetriBarKit
import SwiftUI

struct ProcessesView: View {
    let monitor: ServerMonitor

    @State private var sortOrder = [KeyPathComparator(\ProcessRow.cpu, order: .reverse)]
    @State private var search = ""
    @State private var selection: ProcessRow.ID?
    @State private var showsCommandLine = false

    var body: some View {
        if monitor.snapshot.processes == nil {
            FeedPlaceholder(monitor: monitor, feed: .processes)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                summary
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("PID", value: \.pid) { NumberCell(text: String($0.pid)) }
                        .width(min: 50, ideal: 60)
                    TableColumn("Name", value: \.name)
                    TableColumn("User", value: \.user).width(min: 60, ideal: 90)
                    TableColumn("CPU", value: \.cpu) { NumberCell(text: Format.percent($0.cpu)) }
                        .width(min: 50, ideal: 60)
                    TableColumn("Memory", value: \.memory) { NumberCell(text: Format.percent($0.memory)) }
                        .width(min: 60, ideal: 70)
                    TableColumn("Resident", value: \.resident) { NumberCell(text: Format.bytes($0.resident)) }
                        .width(min: 70, ideal: 80)
                    TableColumn("Threads", value: \.threads) { NumberCell(text: String($0.threads)) }
                        .width(min: 50, ideal: 60)
                    TableColumn("Status", value: \.status).width(min: 40, ideal: 50)
                }
            }
            .padding()
            .searchable(text: $search, prompt: Text("Name or user"))
            .inspector(isPresented: .constant(selection != nil)) {
                inspector
                    .inspectorColumnWidth(min: 220, ideal: 260)
            }
            .onChange(of: selection) { showsCommandLine = false }
        }
    }

    private var summary: some View {
        let count = monitor.snapshot.processCount
        let shown = monitor.snapshot.processes?.count ?? 0
        return Text(
            "Top \(shown) of \(count?.total ?? shown) processes, as sorted by the server. \(count?.thread ?? 0) threads."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var rows: [ProcessRow] {
        let all = (monitor.snapshot.processes ?? []).compactMap(ProcessRow.init)
        let filtered =
            search.isEmpty
            ? all
            : all.filter {
                $0.name.localizedCaseInsensitiveContains(search) || $0.user.localizedCaseInsensitiveContains(search)
            }
        return filtered.sorted(using: sortOrder)
    }

    @ViewBuilder
    private var inspector: some View {
        if let selection, let process = monitor.snapshot.processes?.first(where: { $0.pid == selection }) {
            Form {
                LabeledContent("Name", value: process.name ?? "–")
                LabeledContent("PID", value: process.pid.map(String.init) ?? "–")
                LabeledContent("User", value: process.username ?? "–")
                LabeledContent("CPU", value: Format.percent(process.cpuPercent))
                LabeledContent("Memory", value: Format.percent(process.memoryPercent))
                LabeledContent("Resident", value: Format.bytes(process.memoryInfo?.rss))
                LabeledContent("Virtual", value: Format.bytes(process.memoryInfo?.vms))
                LabeledContent("Threads", value: process.numThreads.map(String.init) ?? "–")
                LabeledContent("Nice", value: process.nice.map(String.init) ?? "–")
                Section("Command Line") {
                    if showsCommandLine {
                        Text((process.cmdline ?? []).joined(separator: " "))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } else {
                        // Arguments can contain secrets such as tokens.
                        Button("Show Command Line") { showsCommandLine = true }
                        Text("May contain passwords or tokens passed as arguments.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            Text("No process selected").foregroundStyle(.secondary)
        }
    }
}

/// Plain data for the table; `nonisolated` so its key paths are `Sendable`
/// for `KeyPathComparator` despite the app's `MainActor` default isolation.
nonisolated struct ProcessRow: Identifiable, Sendable {
    let id: Int
    let pid: Int
    let name: String
    let user: String
    let cpu: Double
    let memory: Double
    let resident: Double
    let threads: Int
    let status: String

    init?(_ process: ProcessEntry) {
        guard let pid = process.pid else { return nil }
        id = pid
        self.pid = pid
        name = process.name ?? "–"
        user = process.username ?? "–"
        cpu = process.cpuPercent ?? 0
        memory = process.memoryPercent ?? 0
        resident = process.memoryInfo?.rss ?? 0
        threads = process.numThreads ?? 0
        status = process.status ?? ""
    }
}
