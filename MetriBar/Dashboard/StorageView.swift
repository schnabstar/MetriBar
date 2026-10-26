import MetriBarKit
import SwiftUI

/// File systems and disk I/O as two edge-to-edge tables in a split view,
/// like Disk Utility and Activity Monitor.
struct StorageView: View {
    let monitor: ServerMonitor

    @State private var fileSystemOrder = [KeyPathComparator(\FileSystemRow.percent, order: .reverse)]
    @State private var diskOrder = [KeyPathComparator(\DiskRow.name)]

    var body: some View {
        if monitor.snapshot.fileSystems == nil {
            FeedPlaceholder(monitor: monitor, feed: .storage)
        } else {
            VSplitView {
                Table(fileSystems.sorted(using: fileSystemOrder), sortOrder: $fileSystemOrder) {
                    TableColumn("Mount Point", value: \.mount)
                    TableColumn("Device", value: \.device)
                    TableColumn("Type", value: \.type).width(min: 50, ideal: 60)
                    TableColumn("Used", value: \.used) { Text(Format.bytes($0.used)) }
                        .width(min: 70, ideal: 80)
                        .alignment(.numeric)
                    TableColumn("Size", value: \.size) { Text(Format.bytes($0.size)) }
                        .width(min: 70, ideal: 80)
                        .alignment(.numeric)
                    TableColumn("Usage", value: \.percent) { PercentCell(percent: $0.percent, level: $0.level) }
                        .width(min: 120, ideal: 160)
                }
                .frame(minHeight: 120, idealHeight: 260)
                Table(disks.sorted(using: diskOrder), sortOrder: $diskOrder) {
                    TableColumn("Disk", value: \.name)
                    TableColumn("Read", value: \.readBytes) { Text(Format.bytesPerSecond($0.readBytes)) }
                        .alignment(.numeric)
                    TableColumn("Write", value: \.writeBytes) { Text(Format.bytesPerSecond($0.writeBytes)) }
                        .alignment(.numeric)
                    TableColumn("Read IOPS", value: \.readCount) {
                        Text(Format.number($0.readCount, fractionDigits: 1))
                    }
                    .alignment(.numeric)
                    TableColumn("Write IOPS", value: \.writeCount) {
                        Text(Format.number($0.writeCount, fractionDigits: 1))
                    }
                    .alignment(.numeric)
                    TableColumn("Latency", value: \.latency) {
                        Text("\(Format.number($0.latency, fractionDigits: 1)) ms")
                    }
                    .alignment(.numeric)
                }
                .frame(minHeight: 100)
            }
            .monospacedDigit()
            .scrollEdgeEffectStyle(.hard, for: .top)
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
