import Foundation
import Observation

/// Owns one `ServerMonitor` per configured server and summarizes their
/// health for the menu bar.
@MainActor
@Observable
public final class MonitorCenter {
    /// Monitors in the order of the configuration.
    public private(set) var monitors: [ServerMonitor] = []
    public private(set) var settings: PollingSettings

    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let makeClient: @MainActor (ServerConfig) -> GlancesClient

    public init(
        settings: PollingSettings = PollingSettings(),
        clock: any Clock<Duration> = ContinuousClock(),
        makeClient: @escaping @MainActor (ServerConfig) -> GlancesClient
    ) {
        self.settings = settings
        self.clock = clock
        self.makeClient = makeClient
    }

    /// Worst health of all enabled servers.
    public var health: ServerHealth {
        monitors.filter { $0.config.isEnabled }.map(\.health).max() ?? .unknown
    }

    public func monitor(for id: UUID) -> ServerMonitor? {
        monitors.first { $0.id == id }
    }

    /// Creates, updates, reorders and removes monitors to match `configs`.
    public func apply(_ configs: [ServerConfig]) {
        var seen = Set<UUID>()
        let configs = configs.filter { seen.insert($0.id).inserted }
        let existing = Dictionary(monitors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        monitors = configs.map { config in
            if let monitor = existing[config.id] {
                if monitor.config != config {
                    monitor.update(config: config, client: makeClient(config))
                }
                return monitor
            }
            let monitor = ServerMonitor(config: config, client: makeClient(config), settings: settings, clock: clock)
            monitor.start()
            return monitor
        }
        for (id, monitor) in existing where !seen.contains(id) {
            monitor.stop()
        }
    }

    /// Rebuilds the client of one server, for example after its password
    /// changed in the Keychain.
    public func reconnect(_ id: UUID) {
        guard let monitor = monitor(for: id) else { return }
        monitor.update(config: monitor.config, client: makeClient(monitor.config))
    }

    public func update(settings: PollingSettings) {
        self.settings = settings
        for monitor in monitors {
            monitor.update(settings: settings)
        }
    }

    public func refreshAll() {
        for monitor in monitors where monitor.config.isEnabled {
            monitor.refresh()
        }
    }

    public func handle(_ event: SystemEvent) {
        for monitor in monitors {
            switch event {
            case .willSleep: monitor.pause()
            case .didWake, .networkChanged: monitor.resume()
            }
        }
    }

    public func stopAll() {
        for monitor in monitors {
            monitor.stop()
        }
    }
}
