import MetriBarKit
import SwiftUI

/// Sortable iPad table with a trailing inspector for the selected container.
struct IPadContainersView: View {
    let monitor: ServerMonitor

    @State private var sortOrder = [KeyPathComparator(\ContainerTableRow.cpu, order: .reverse)]
    @State private var search = ""
    @State private var runningOnly = false
    @State private var selection: ContainerTableRow.ID?
    @State private var showsInspector = false

    var body: some View {
        Group {
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
                table
            }
        }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                Label {
                    Text(row.name)
                } icon: {
                    Image(systemName: row.symbol).foregroundStyle(row.color).imageScale(.small)
                }
            }
            TableColumn("Status", value: \.status).width(min: 60, ideal: 80)
            TableColumn("Image", value: \.image)
            TableColumn("CPU", value: \.cpu) { Text($0.cpuText) }
                .width(min: 60, ideal: 80)
                .alignment(.numeric)
            TableColumn("Memory", value: \.memory) { Text($0.memoryText) }
                .width(min: 90, ideal: 130)
                .alignment(.numeric)
            TableColumn("Network", value: \.network) { row in
                Text(verbatim: "↓ \(Format.bitsPerSecond(row.networkRx)) ↑ \(Format.bitsPerSecond(row.networkTx))")
            }
            .width(min: 120, ideal: 150)
            .alignment(.numeric)
            TableColumn("Disk I/O", value: \.io) { row in
                Text(verbatim: "R \(Format.bytesPerSecond(row.ioRead)) W \(Format.bytesPerSecond(row.ioWrite))")
            }
            .width(min: 120, ideal: 150)
            .alignment(.numeric)
            TableColumn("Up", value: \.started) { Text($0.uptimeText) }
                .width(min: 60, ideal: 70)
                .alignment(.numeric)
            TableColumn("Ports", value: \.ports)
        }
        .monospacedDigit()
        .searchable(text: $search, prompt: Text("Name or image"))
        .inspector(isPresented: $showsInspector) {
            inspector
                .inspectorColumnWidth(min: 250, ideal: 320)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $runningOnly) {
                    Label("Running Only", systemImage: "line.3.horizontal.decrease.circle")
                        .symbolVariant(runningOnly ? .fill : .none)
                }
                .help("Show only running containers")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Container Details", systemImage: "sidebar.trailing") { showsInspector.toggle() }
                    .help("Show or hide the selected container details")
            }
        }
        .onChange(of: selection) { _, value in
            if value != nil { showsInspector = true }
        }
    }

    private var rows: [ContainerTableRow] {
        let now = Date.now
        let all = (monitor.snapshot.containers?.items ?? []).compactMap { ContainerTableRow($0, now: now) }
        let matching = all.filter { row in
            (!runningOnly || row.isRunning)
                && (search.isEmpty || row.name.localizedCaseInsensitiveContains(search)
                    || row.image.localizedCaseInsensitiveContains(search))
        }
        return matching.sorted(using: sortOrder)
    }

    @ViewBuilder
    private var inspector: some View {
        if let selection, let row = rows.first(where: { $0.id == selection }) {
            Form {
                Section("Container") {
                    LabeledContent("Name", value: row.name)
                    LabeledContent("Status", value: row.status.capitalized)
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
                        Text(row.ports).font(.caption.monospaced()).textSelection(.enabled)
                        Button("Copy Ports", systemImage: "doc.on.doc") { Clipboard.copy(row.ports) }
                    }
                }
            }
            .formStyle(.grouped)
            .monospacedDigit()
        } else {
            ContentUnavailableView("No Container Selected", systemImage: "shippingbox")
        }
    }
}
