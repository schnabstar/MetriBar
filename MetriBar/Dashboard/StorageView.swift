import MetriBarKit
import SwiftUI

struct StorageView: View {
    let monitor: ServerMonitor

    @State private var fileSystemOrder = [KeyPathComparator(\FileSystemRow.percent, order: .reverse)]
    @State private var diskOrder = [KeyPathComparator(\DiskRow.name)]

    var body: some View {
        if monitor.snapshot.fileSystems == nil {
            FeedPlaceholder(monitor: monitor, feed: .storage)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                DashboardGroup(title: String(localized: "File Systems")) {
                    Table(fileSystems.sorted(using: fileSystemOrder), sortOrder: $fileSystemOrder) {
                        TableColumn("Mount Point", value: \.mount)
                        TableColumn("Device", value: \.device)
                        TableColumn("Type", value: \.type).width(min: 50, ideal: 60)
                        TableColumn("Used", value: \.used) { NumberCell(text: Format.bytes($0.used)) }
                            .width(min: 70, ideal: 80)
                        TableColumn("Size", value: \.size) { NumberCell(text: Format.bytes($0.size)) }
                            .width(min: 70, ideal: 80)
                        TableColumn("Usage", value: \.percent) { PercentCell(percent: $0.percent, level: $0.level) }
                            .width(min: 120, ideal: 160)
                    }
                    .frame(minHeight: 140)
                }
                DashboardGroup(title: String(localized: "Disk I/O")) {
                    Table(disks.sorted(using: diskOrder), sortOrder: $diskOrder) {
                        TableColumn("Disk", value: \.name)
                        TableColumn("Read", value: \.readBytes) {
                            NumberCell(text: Format.bytesPerSecond($0.readBytes))
                        }
                        TableColumn("Write", value: \.writeBytes) {
                            NumberCell(text: Format.bytesPerSecond($0.writeBytes))
                        }
                        TableColumn("Read IOPS", value: \.readCount) {
                            NumberCell(text: Format.number($0.readCount, fractionDigits: 1))
                        }
                        TableColumn("Write IOPS", value: \.writeCount) {
                            NumberCell(text: Format.number($0.writeCount, fractionDigits: 1))
                        }
                        TableColumn("Latency", value: \.latency) {
                            NumberCell(text: String(localized: "\(Format.number($0.latency, fractionDigits: 1)) ms"))
                        }
                    }
                    .frame(minHeight: 120)
                }
                if let swap = monitor.snapshot.swap {
                    MeterRow(
                        title: String(localized: "Swap"), percent: swap.value.percent, level: swap.level("percent"),
                        detail: "\(Format.bytes(swap.value.used)) / \(Format.bytes(swap.value.total))")
                }
            }
            .padding()
        }
    }

    private var fileSystems: [FileSystemRow] {
        guard let collection = monitor.snapshot.fileSystems else { return [] }
        return collection.items.compactMap { item in
            guard let mount = item.mntPoint else { return nil }
            return FileSystemRow(
                id: mount, mount: mount, device: item.deviceName ?? "", type: item.fsType ?? "",
                used: item.used ?? 0, size: item.size ?? 0, percent: item.percent ?? 0,
                level: collection.level("percent", item: mount))
        }
    }

    private var disks: [DiskRow] {
        (monitor.snapshot.diskIO?.items ?? []).compactMap { item in
            guard let name = item.diskName, item.hidden != true else { return nil }
            return DiskRow(
                id: name, name: name, readBytes: item.readBytes ?? 0, writeBytes: item.writeBytes ?? 0,
                readCount: item.readCount ?? 0, writeCount: item.writeCount ?? 0,
                latency: max(item.readLatency ?? 0, item.writeLatency ?? 0))
        }
    }
}

/// Plain data for the table; `nonisolated` so its key paths are `Sendable`
/// for `KeyPathComparator` despite the app's `MainActor` default isolation.
nonisolated struct FileSystemRow: Identifiable, Sendable {
    let id: String
    let mount: String
    let device: String
    let type: String
    let used: Double
    let size: Double
    let percent: Double
    let level: Level
}

/// Plain data for the table; `nonisolated` so its key paths are `Sendable`
/// for `KeyPathComparator` despite the app's `MainActor` default isolation.
nonisolated struct DiskRow: Identifiable, Sendable {
    let id: String
    let name: String
    let readBytes: Double
    let writeBytes: Double
    let readCount: Double
    let writeCount: Double
    let latency: Double
}
