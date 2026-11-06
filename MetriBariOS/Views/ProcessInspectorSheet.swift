import MetriBarKit
import SwiftUI

struct ProcessInspectorSheet: View {
    let process: ProcessEntry
    @Environment(\.dismiss) private var dismiss
    @State private var showsCommandLine = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Process") {
                    LabeledContent("Name", value: process.name ?? "–")
                    LabeledContent("PID", value: process.pid.map(String.init) ?? "–")
                    LabeledContent("User", value: process.username ?? "–")
                    LabeledContent("Status", value: process.status ?? "–")
                    LabeledContent("Threads", value: process.numThreads.map(String.init) ?? "–")
                    LabeledContent("Nice", value: process.nice.map(String.init) ?? "–")
                }

                Section("Resource Usage") {
                    LabeledContent("CPU", value: Format.percent(process.cpuPercent))
                    LabeledContent("Memory", value: Format.percent(process.memoryPercent))
                    LabeledContent("Resident Memory", value: Format.bytes(process.memoryInfo?.rss))
                    LabeledContent("Virtual Memory", value: Format.bytes(process.memoryInfo?.vms))
                }

                Section {
                    if showsCommandLine {
                        let cmd = (process.cmdline ?? []).joined(separator: " ")
                        Text(cmd.isEmpty ? "None" : cmd)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button("Copy Command Line", systemImage: "doc.on.doc") {
                            Clipboard.copy(cmd)
                        }
                    } else {
                        Button("Show Command Line", systemImage: "eye") {
                            showsCommandLine = true
                        }
                        Text("May contain passwords or tokens passed as arguments.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Command Line")
                }
            }
            .monospacedDigit()
            .navigationTitle(process.name ?? "Process Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
