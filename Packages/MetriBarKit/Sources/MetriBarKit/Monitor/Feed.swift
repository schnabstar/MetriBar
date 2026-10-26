/// A group of endpoints that is fetched together. Views keep the feeds they
/// show active with `ServerMonitor.keepActive(_:)`.
public enum Feed: Hashable, Sendable, CaseIterable {
    /// cpu, mem, load, uptime: menu bar, popover and dashboard header.
    case core
    case containers
    /// quicklook, processcount, memswap: dashboard overview.
    case overview
    /// fs, diskio, memswap
    case storage
    case network
    /// sensors and, if present, gpu
    case sensors
    /// processcount and the top processes
    case processes
    /// alert events and incidents
    case alerts
    /// cpu, mem, load and network history, refreshed less often
    case history

    /// Feeds every monitor fetches, also when no view is visible.
    public static let background: Set<Feed> = [.core, .containers]
}

public struct PollingSettings: Sendable, Equatable {
    /// Interval while only the menu bar needs data.
    public var baseInterval: Duration
    /// Interval while the popover or the dashboard shows the server.
    public var liveInterval: Duration
    /// Minimum time between two history downloads.
    public var historyInterval: Duration
    /// Upper bound for the delay after repeated failures.
    public var maxBackoff: Duration
    /// Consecutive failures after which the last values count as stale.
    public var staleAfterFailures: Int
    public var topProcessCount: Int

    public init(
        baseInterval: Duration = .seconds(10),
        liveInterval: Duration = .seconds(2),
        historyInterval: Duration = .seconds(30),
        maxBackoff: Duration = .seconds(60),
        staleAfterFailures: Int = 3,
        topProcessCount: Int = 50
    ) {
        self.baseInterval = baseInterval
        self.liveInterval = liveInterval
        self.historyInterval = historyInterval
        self.maxBackoff = maxBackoff
        self.staleAfterFailures = staleAfterFailures
        self.topProcessCount = topProcessCount
    }
}
