import MetriBarKit
import SwiftUI

struct CompactContainersView: View {
    let monitor: ServerMonitor

    @State private var search = ""
    @State private var runningOnly = false
    @State private var selectedContainer: ContainerTableRow?

    var body: some View {
        let snapshot = monitor.snapshot
        if !snapshot.plugins.isEmpty, !snapshot.plugins.contains("containers") {
            ContentUnavailableView(
                "Containers Plugin Not Active", systemImage: "shippingbox",
                description: Text("Glances on this server does not publish container data."))
        } else if snapshot.containers == nil {
            FeedPlaceholder(monitor: monitor, feed: .containers)
        } else if snapshot.containers?.items.isEmpty == true {
            ContentUnavailableView(
                "No Containers", systemImage: "shippingbox",
                description: Text("Glances reports no containers. Does it have access to the Docker or Podman socket?"))
        } else {
            VStack(spacing: 0) {
                HStack {
                    Toggle("Running Only", isOn: $runningOnly)
                        .font(.caption)
                    Spacer()
                    Text("\(rows.count) containers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    ForEach(rows) { row in
                        Button {
                            selectedContainer = row
                        } label: {
                            ContainerListRow(row: row)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Show Details", systemImage: "info.circle") {
                                selectedContainer = row
                            }
                            Divider()
                            Button("Copy Name", systemImage: "doc.on.doc") { Clipboard.copy(row.name) }
                            if !row.ports.isEmpty {
                                Button("Copy Ports", systemImage: "network") { Clipboard.copy(row.ports) }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $search, prompt: Text("Search containers or images"))
            }
            .sheet(item: $selectedContainer) { row in
                ContainerDetailSheet(row: row)
            }
        }
    }

    private var rows: [ContainerTableRow] {
        let now = Date()
        let all = (monitor.snapshot.containers?.items ?? []).compactMap { ContainerTableRow($0, now: now) }
        let filtered = search.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.image.localizedCaseInsensitiveContains(search)
        }
        let runningFiltered = runningOnly ? filtered.filter(\.isRunning) : filtered
        return runningFiltered.sorted { r1, r2 in
            // Running/unhealthy first, then by name
            if r1.isUnhealthy != r2.isUnhealthy { return r1.isUnhealthy }
            if r1.isRunning != r2.isRunning { return r1.isRunning }
            return r1.name.localizedCaseInsensitiveCompare(r2.name) == .orderedAscending
        }
    }
}

private struct ContainerListRow: View {
    let row: ContainerTableRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: row.symbol)
                .foregroundStyle(row.color)
                .imageScale(.medium)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(row.image.isEmpty ? row.status : row.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if row.isRunning {
                    Text(row.cpuText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(row.memoryText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(row.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
