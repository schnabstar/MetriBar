import Foundation

/// A current value of a server, read for a rule.
public struct MetricValue: Sendable, Equatable {
    /// Mount point or sensor label; `nil` for values of the whole server.
    public var item: String?
    /// In the unit of the metric, see `RuleMetric.Unit`.
    public var value: Double

    public init(item: String? = nil, value: Double) {
        self.item = item
        self.value = value
    }
}

/// Reads the value a rule is about from what is known of a server.
public enum MetricReader {
    /// The values of `metric`: one for most metrics, one per file system or
    /// sensor for `disk` and `temperature` without a chosen item. Empty if
    /// the data is not there.
    public static func read(_ metric: RuleMetric, from snapshot: ServerSnapshot) -> [MetricValue] {
        switch metric.kind {
        case .cpu:
            return single(snapshot.cpu?.value.total)
        case .memory:
            return single(snapshot.memory?.value.percent)
        case .swap:
            return single(snapshot.swap?.value.percent)
        case .load:
            return single(snapshot.load?.value.min5)
        case .disk:
            return (snapshot.fileSystems?.items ?? []).compactMap { fileSystem in
                guard let mount = fileSystem.mntPoint, let percent = fileSystem.percent, percent.isFinite,
                    metric.item == nil || metric.item == mount
                else { return nil }
                return MetricValue(item: mount, value: percent)
            }
        case .temperature:
            return (snapshot.sensors?.items ?? []).compactMap { sensor in
                guard sensor.kind == .temperature, let label = sensor.label, let value = sensor.value, value.isFinite,
                    metric.item == nil || metric.item == label
                else { return nil }
                return MetricValue(item: label, value: value)
            }
        case .networkDown:
            return single(throughput(snapshot, \.bytesRecv))
        case .networkUp:
            return single(throughput(snapshot, \.bytesSent))
        }
    }

    private static func single(_ value: Double?) -> [MetricValue] {
        guard let value, value.isFinite else { return [] }
        return [MetricValue(value: value)]
    }

    /// Megabytes per second over all interfaces that are up, without the
    /// loopback interface. `nil` while the data is missing.
    private static func throughput(
        _ snapshot: ServerSnapshot, _ rate: KeyPath<NetworkInterface, Double?>
    ) -> Double? {
        guard let interfaces = snapshot.network?.items else { return nil }
        let bytes =
            interfaces
            .filter { $0.isUp != false && $0.hidden != true && !isLoopback($0.interfaceName) }
            .compactMap { $0[keyPath: rate] }
            .filter(\.isFinite)
            .reduce(0, +)
        return bytes / 1_000_000
    }

    private static func isLoopback(_ name: String?) -> Bool {
        guard let name else { return false }
        return name == "lo" || name.hasPrefix("lo0")
    }
}
