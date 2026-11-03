import Foundation

/// The last values of one metric, oldest first.
public struct SampleHistory: Sendable, Equatable {
    /// With a sample every ten seconds this is five minutes.
    public static let capacity = 30

    public private(set) var values: [Double] = []

    public init() {}

    public mutating func append(_ value: Double) {
        guard value.isFinite else { return }
        values.append(value)
        if values.count > Self.capacity { values.removeFirst(values.count - Self.capacity) }
    }
}

extension MenuBarMetric {
    /// The range a trend line is drawn in: percentages always over 0 to
    /// 100, so a quiet CPU does not look like a storm; `nil` for the rest,
    /// which fit themselves to their values.
    public var fixedRange: ClosedRange<Double>? {
        switch self {
        case .cpu, .memory, .swap, .disk: 0...100
        default: nil
        }
    }
}

/// Keeps the recent values of the menu bar items of one server, for the
/// trend line. Glances keeps a history of its own, but only for a few
/// values and only while the dashboard asks for it.
public struct MenuBarSampler: Sendable, Equatable {
    public private(set) var serverID: UUID?
    private var histories: [MenuBarMetric: SampleHistory] = [:]

    public init() {}

    public func history(for metric: MenuBarMetric) -> [Double] {
        histories[metric]?.values ?? []
    }

    /// Takes one sample of every item. Another server starts a new history;
    /// items that were removed are forgotten. Without a `snapshot` (the
    /// server cannot be read) nothing is recorded, so a gap is not drawn as
    /// a value.
    public mutating func record(serverID: UUID?, items: [MenuBarMetric], snapshot: ServerSnapshot?) {
        if serverID != self.serverID {
            self.serverID = serverID
            histories = [:]
        }
        histories = histories.filter { items.contains($0.key) }
        guard let snapshot else { return }
        for item in Preferences.normalized(items) {
            guard let value = MenuBarText.value(item, from: snapshot) else { continue }
            histories[item, default: SampleHistory()].append(value)
        }
    }
}
