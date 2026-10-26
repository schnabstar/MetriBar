import AppKit
import MetriBarKit
import SwiftUI

struct ProcessesView: View {
    let monitor: ServerMonitor

    @State private var sortOrder = [KeyPathComparator(\ProcessRow.cpu, order: .reverse)]
    @State private var search = ""
    @State private var selection: ProcessRow.ID?
    @State private var showsCommandLine = false
    @SceneStorage("showsProcessInspector") private var showsInspector = false

    var body: some View {
        if monitor.snapshot.processes == nil {
            FeedPlaceholder(monitor: monitor, feed: .processes)
        } else {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("PID", value: \.pid) { Text(String($0.pid)) }
                    .width(min: 50, ideal: 60)
                    .alignment(.numeric)
                TableColumn("Name", value: \.name)
                TableColumn("User", value: \.user).width(min: 60, ideal: 90)
                TableColumn("CPU", value: \.cpu) { Text(Format.percent($0.cpu)) }
                    .width(min: 50, ideal: 60)
                    .alignment(.numeric)
                TableColumn("Memory", value: \.memory) { Text(Format.percent($0.memory)) }
                    .width(min: 60, ideal: 70)
                    .alignment(.numeric)
                TableColumn("Resident", value: \.resident) { Text(Format.bytes($0.resident)) }
                    .width(min: 70, ideal: 80)
                    .alignment(.numeric)
                TableColumn("Threads", value: \.threads) { Text(String($0.threads)) }
                    .width(min: 50, ideal: 60)
                    .alignment(.numeric)
                TableColumn("Status", value: \.status).width(min: 40, ideal: 50)
            }
            .monospacedDigit()
            .contextMenu(forSelectionType: ProcessRow.ID.self) { ids in
                if let pid = ids.first, let row = rows.first(where: { $0.id == pid }) {
                    Button("Show Details") { showDetails(pid) }
                    Divider()
                    Button("Copy Name") { copy(row.name) }
                    Button("Copy PID") { copy(String(row.pid)) }
                }
            } primaryAction: { ids in
                if let pid = ids.first { showDetails(pid) }
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
            .searchable(text: $search, prompt: Text("Name or user"))
            .inspector(isPresented: $showsInspector) {
                inspector
                    .inspectorColumnWidth(min: 220, ideal: 260)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Process Details", systemImage: "sidebar.trailing") { showsInspector.toggle() }
                        .keyboardShortcut("i", modifiers: [.command, .option])
                        .help("Show or hide the details of the selected process")
                }
            }
            .onChange(of: selection) { showsCommandLine = false }
        }
    }

    /// "Top 50 of 405 processes …" for the window subtitle.
    static func summary(_ snapshot: ServerSnapshot) -> String? {
        guard let processes = snapshot.processes else { return nil }
        let count = snapshot.processCount
        return String(
            localized:
                "Top \(processes.count) of \(count?.total ?? processes.count) processes, as sorted by the server. \(count?.thread ?? 0) threads."
        )
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

    private func showDetails(_ pid: ProcessRow.ID) {
        selection = pid
        showsInspector = true
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
            .monospacedDigit()
        } else {
            ContentUnavailableView(
                "No Process Selected", systemImage: "list.bullet.rectangle",
                description: Text("Select a process to see its details."))
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
