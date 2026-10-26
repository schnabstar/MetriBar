import MetriBarKit
import SwiftUI

struct NetworkView: View {
    let monitor: ServerMonitor

    @State private var interfaceOrder = [KeyPathComparator(\InterfaceRow.received, order: .reverse)]

    var body: some View {
        if monitor.snapshot.network == nil {
            FeedPlaceholder(monitor: monitor, feed: .network)
        } else {
            Table(interfaces.sorted(using: interfaceOrder), sortOrder: $interfaceOrder) {
                TableColumn("Interface", value: \.name) { row in
                    Label {
                        Text(row.name)
                    } icon: {
                        Image(systemName: row.isUp ? "circle.fill" : "circle")
                            .foregroundStyle(row.isUp ? .green : .secondary)
                            .imageScale(.small)
                    }
                }
                TableColumn("Received", value: \.received) { Text(Format.bytesPerSecond($0.received)) }
                    .alignment(.numeric)
                TableColumn("Sent", value: \.sent) { Text(Format.bytesPerSecond($0.sent)) }
                    .alignment(.numeric)
                TableColumn("Total Received", value: \.totalReceived) { Text(Format.bytes($0.totalReceived)) }
                    .alignment(.numeric)
                TableColumn("Total Sent", value: \.totalSent) { Text(Format.bytes($0.totalSent)) }
                    .alignment(.numeric)
                TableColumn("Link", value: \.linkSpeed) {
                    Text($0.linkSpeed > 0 ? Format.bytesPerSecond($0.linkSpeed) : Format.placeholder)
                }
                .alignment(.numeric)
            }
            .monospacedDigit()
            .scrollEdgeEffectStyle(.hard, for: .top)
        }
    }

    private var interfaces: [InterfaceRow] {
        (monitor.snapshot.network?.items ?? []).compactMap { item in
            guard let name = item.interfaceName, item.hidden != true else { return nil }
            return InterfaceRow(
                id: name, name: name, isUp: item.isUp ?? false, received: item.bytesRecv ?? 0,
                sent: item.bytesSent ?? 0, totalReceived: item.bytesRecvCumul ?? 0,
                totalSent: item.bytesSentCumul ?? 0, linkSpeed: item.linkSpeed ?? 0)
        }
    }
}

/// Plain data for the table; `nonisolated` so its key paths are `Sendable`
/// for `KeyPathComparator` despite the app's `MainActor` default isolation.
nonisolated struct InterfaceRow: Identifiable, Sendable {
    let id: String
    let name: String
    let isUp: Bool
    let received: Double
    let sent: Double
    let totalReceived: Double
    let totalSent: Double
    let linkSpeed: Double
}
