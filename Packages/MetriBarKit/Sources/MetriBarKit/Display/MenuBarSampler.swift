import Foundation

/// The last values of one metric, oldest first. A `nil` is a sample that
/// could not be taken, for example because the server was unreadable: it
/// keeps its place, so the trend shows a gap instead of joining the values
/// before and after it.
public struct SampleHistory: Sendable, Equatable {
    /// With a sample every ten seconds this is five minutes.
    public static let capacity = 30

    public private(set) var values: [Double?] = []

    public init() {}

    /// A value that is not a finite number counts as a gap.
    public mutating func append(_ value: Double?) {
        values.append(value.flatMap { $0.isFinite ? $0 : nil })
        if values.count > Self.capacity { values.removeFirst(values.count - Self.capacity) }
    }

    /// Whether there is a value to draw a line through.
    public var hasValues: Bool {
        values.contains { $0 != nil }
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

    public func history(for metric: MenuBarMetric) -> [Double?] {
        histories[metric]?.values ?? []
    }

    /// Takes one sample of every item. Another server starts a new history;
    /// items that were removed are forgotten. Without a `snapshot` (the
    /// server cannot be read), or if it lacks a value, the sample is a gap,
    /// once there is something before it: a history does not start with a gap.
    public mutating func record(serverID: UUID?, items: [MenuBarMetric], snapshot: ServerSnapshot?) {
        if serverID != self.serverID {
            self.serverID = serverID
            histories = [:]
        }
        histories = histories.filter { items.contains($0.key) }
        for item in Preferences.normalized(items) {
            let value = snapshot.flatMap { MenuBarText.value(item, from: $0) }
            var history = histories[item] ?? SampleHistory()
            guard value != nil || history.hasValues else { continue }
            history.append(value)
            histories[item] = history
        }
    }
}

/// A point of a trend line in the unit square: `x` from the oldest sample
/// (0) to the newest (1), `y` from the bottom (0) to the top (1).
public struct TrendPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
}

public enum TrendLayout {
    /// The lines to draw: one per run of samples without a gap. A single
    /// sample between two gaps is a run of one point.
    ///
    /// - Parameter range: Where the bottom and top lie; `nil` fits them to
    ///   the values. A line whose values are all equal runs through the
    ///   middle.
    public static func segments(_ values: [Double?], range: ClosedRange<Double>? = nil) -> [[TrendPoint]] {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return [] }
        let low = range?.lowerBound ?? present.min()!
        let high = range?.upperBound ?? present.max()!
        let flat = high - low < 0.000_001
        let lastIndex = max(values.count - 1, 1)

        var segments: [[TrendPoint]] = []
        var current: [TrendPoint] = []
        for (index, value) in values.enumerated() {
            guard let value else {
                if !current.isEmpty { segments.append(current) }
                current = []
                continue
            }
            let y = flat ? 0.5 : min(max((value - low) / (high - low), 0), 1)
            current.append(TrendPoint(x: Double(index) / Double(lastIndex), y: y))
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}
