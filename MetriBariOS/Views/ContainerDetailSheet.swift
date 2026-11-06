import MetriBarKit
import SwiftUI

struct ContainerDetailSheet: View {
    let row: ContainerTableRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Container") {
                    LabeledContent("Name", value: row.name)
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Image(systemName: row.symbol)
                                .foregroundStyle(row.color)
                                .imageScale(.small)
                            Text(row.status.capitalized)
                        }
                    }
                    LabeledContent("Image", value: row.image.isEmpty ? "–" : row.image)
                    LabeledContent("Uptime", value: row.uptimeText)
                }

                Section("Resources") {
                    LabeledContent("CPU", value: row.cpuText)
                    LabeledContent("Memory", value: row.memoryText)
                    LabeledContent("Network I/O") {
                        Text(verbatim: "↓ \(Format.bitsPerSecond(row.networkRx))  ↑ \(Format.bitsPerSecond(row.networkTx))")
                    }
                    LabeledContent("Disk I/O") {
                        Text(verbatim: "R \(Format.bytesPerSecond(row.ioRead))  W \(Format.bytesPerSecond(row.ioWrite))")
                    }
                }

                if !row.ports.isEmpty {
                    Section("Port Mappings") {
                        Text(row.ports)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button("Copy Ports", systemImage: "doc.on.doc") {
                            Clipboard.copy(row.ports)
                        }
                    }
                }
            }
            .monospacedDigit()
            .navigationTitle(row.name)
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
