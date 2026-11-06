import MetriBarKit
import SwiftUI

/// Network rates and totals in cards that fit an iPhone screen.
struct CompactNetworkView: View {
    let monitor: ServerMonitor

    var body: some View {
        if monitor.snapshot.network == nil {
            FeedPlaceholder(monitor: monitor, feed: .network)
        } else if interfaces.isEmpty {
            ContentUnavailableView("No Interfaces", systemImage: "network", description: Text("Glances reports no network interfaces."))
        } else {
            VStack(spacing: 12) {
                ForEach(interfaces) { interface in
                    interfaceCard(interface)
                }
            }
            .padding()
        }
    }

    private func interfaceCard(_ interface: InterfaceRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: interface.isUp ? "circle.fill" : "circle")
                    .foregroundStyle(interface.isUp ? .green : .secondary)
                    .imageScale(.small)
                Text(interface.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if interface.linkSpeed > 0 {
                    Text(Format.bytesPerSecond(interface.linkSpeed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                rate(label: "Received", value: interface.received, symbol: "arrow.down", color: .blue)
                rate(label: "Sent", value: interface.sent, symbol: "arrow.up", color: .green)
            }

            Divider()

            HStack(spacing: 16) {
                total(label: "Total received", value: interface.totalReceived)
                total(label: "Total sent", value: interface.totalSent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func rate(label: String, value: Double, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Format.bytesPerSecond(value))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func total(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(Format.bytes(value)).font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var interfaces: [InterfaceRow] {
        (monitor.snapshot.network?.items ?? []).compactMap { item in
            guard let name = item.interfaceName, item.hidden != true else { return nil }
            return InterfaceRow(
                id: name, name: name, isUp: item.isUp ?? false, received: item.bytesRecv ?? 0,
                sent: item.bytesSent ?? 0, totalReceived: item.bytesRecvCumul ?? 0,
                totalSent: item.bytesSentCumul ?? 0, linkSpeed: item.linkSpeed ?? 0)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
