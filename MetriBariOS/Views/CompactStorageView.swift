import MetriBarKit
import SwiftUI

struct CompactStorageView: View {
    let monitor: ServerMonitor

    var body: some View {
        if monitor.snapshot.fileSystems == nil {
            FeedPlaceholder(monitor: monitor, feed: .storage)
        } else {
            VStack(spacing: 20) {
                fileSystemsSection
                disksSection
            }
            .padding()
        }
    }

    private var fileSystemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("File Systems", systemImage: "internaldrive")
                .font(.headline)

            ForEach(fileSystems) { fs in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fs.mount)
                                .font(.subheadline.weight(.semibold))
                            Text("\(fs.device) (\(fs.type))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.percent(fs.percent))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(fs.level.color)
                            Text("\(Format.bytes(fs.used)) / \(Format.bytes(fs.size))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.fill.tertiary)
                            Capsule()
                                .fill(fs.level.color)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(fs.percent / 100.0))))
                        }
                    }
                    .frame(height: 6)
                }
                .padding(14)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var disksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Disk I/O", systemImage: "externaldrive")
                .font(.headline)

            if disks.isEmpty {
                Text("No disk I/O data reported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(disks) { disk in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(disk.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if disk.latency > 0 {
                                Text("\(Format.number(disk.latency, fractionDigits: 1)) ms")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 16) {
                            statItem(label: "Read", value: Format.bytesPerSecond(disk.readBytes))
                            statItem(label: "Write", value: Format.bytesPerSecond(disk.writeBytes))
                            statItem(label: "Read IOPS", value: Format.number(disk.readCount, fractionDigits: 0))
                            statItem(label: "Write IOPS", value: Format.number(disk.writeCount, fractionDigits: 0))
                        }
                    }
                    .padding(14)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
