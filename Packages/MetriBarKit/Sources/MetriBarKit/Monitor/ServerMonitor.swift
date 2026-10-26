import Foundation
import OSLog
import Observation

/// Polls one Glances server and publishes what it knows as `snapshot`.
///
/// The background feeds (core, containers) are fetched every
/// `baseInterval` so the menu bar stays current. Views keep further feeds
/// active with `keepActive(_:)`; while any view does, all active feeds are
/// fetched every `liveInterval`.
@MainActor
@Observable
public final class ServerMonitor: Identifiable {
    public nonisolated let id: UUID
    public private(set) var config: ServerConfig
    public private(set) var state: ConnectionState = .idle
    public private(set) var snapshot = ServerSnapshot()
    /// Errors of individual feeds while the connection itself works, for
    /// example a plugin that fails on this server.
    public private(set) var feedErrors: [Feed: GlancesError] = [:]
    public private(set) var lastSuccess: Date?
    /// `true` after `staleAfterFailures` failed attempts in a row: the values
    /// in `snapshot` are outdated.
    public private(set) var isStale = false
    public private(set) var consecutiveFailures = 0

    @ObservationIgnored private var client: GlancesClient
    @ObservationIgnored private var settings: PollingSettings
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var isPaused = false
    @ObservationIgnored private var needsHandshake = true
    @ObservationIgnored private var subscriptions: [Feed: Int] = [:]
    @ObservationIgnored private var historyAge: Duration?
    @ObservationIgnored private var retryAfter: Duration?

    public init(
        config: ServerConfig,
        client: GlancesClient,
        settings: PollingSettings = PollingSettings(),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.id = config.id
        self.config = config
        self.client = client
        self.settings = settings
        self.clock = clock
    }

    // MARK: - Derived state

    public var displayName: String {
        config.name.isEmpty ? (snapshot.system?.hostname ?? config.displayName) : config.name
    }

    public var health: ServerHealth {
        switch state {
        case .idle, .connecting:
            return .unknown
        case .needsCredentials, .unsupportedVersion:
            return .offline
        case .failed:
            // Tolerate single failures as long as the last values are recent.
            return isStale || lastSuccess == nil ? .offline : dataHealth
        case .connected:
            return dataHealth
        }
    }

    private var dataHealth: ServerHealth {
        let level = snapshot.worstLevel
        if level >= .critical { return .critical }
        if level >= .warning || snapshot.hasUnhealthyContainers { return .warning }
        return .ok
    }

    private var isHalted: Bool {
        switch state {
        case .needsCredentials, .unsupportedVersion: true
        default: false
        }
    }

    private var currentInterval: Duration {
        subscriptions.isEmpty ? settings.baseInterval : settings.liveInterval
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning, config.isEnabled else { return }
        isRunning = true
        isPaused = false
        reschedule(pollNow: true)
    }

    public func stop() {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
        state = .idle
    }

    /// Stops polling until `resume()`, for example while the Mac sleeps.
    public func pause() {
        isPaused = true
        loopTask?.cancel()
        loopTask = nil
    }

    /// Continues polling with an immediate request. Does not retry after the
    /// server rejected the credentials or the version; use `refresh()`.
    public func resume() {
        guard isRunning, !isHalted else { return }
        isPaused = false
        reschedule(pollNow: true)
    }

    /// Polls immediately. Also retries after rejected credentials or an
    /// unsupported version, because the user asked for it.
    public func refresh() {
        guard isRunning else { return start() }
        isPaused = false
        if isHalted { needsHandshake = true }
        reschedule(pollNow: true)
    }

    /// Applies a changed configuration or new credentials.
    public func update(config: ServerConfig, client: GlancesClient) {
        let endpointChanged = config.url != self.config.url || config.username != self.config.username
        self.config = config
        self.client = client
        needsHandshake = true
        if endpointChanged {
            snapshot = ServerSnapshot()
            feedErrors = [:]
            lastSuccess = nil
            isStale = false
            consecutiveFailures = 0
            historyAge = nil
        }
        guard config.isEnabled else { return stop() }
        if isRunning {
            state = .connecting
            reschedule(pollNow: true)
        } else {
            start()
        }
    }

    public func update(settings: PollingSettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        if isRunning, !isPaused, !isHalted { reschedule(pollNow: false) }
    }

    // MARK: - Subscriptions

    /// Keeps `feeds` active until the calling task is cancelled. Use it from
    /// a view's `.task` modifier.
    public func keepActive(_ feeds: Set<Feed>) async {
        addSubscription(feeds)
        defer { removeSubscription(feeds) }
        let (stream, continuation) = AsyncStream<Never>.makeStream()
        await withTaskCancellationHandler {
            for await _ in stream {}
        } onCancel: {
            continuation.finish()
        }
    }

    private func addSubscription(_ feeds: Set<Feed>) {
        let wasLive = !subscriptions.isEmpty
        let newlyActive = feeds.filter { subscriptions[$0, default: 0] == 0 && !Feed.background.contains($0) }
        for feed in feeds {
            subscriptions[feed, default: 0] += 1
        }
        if newlyActive.contains(.history) { historyAge = nil }
        if isRunning, !isPaused, !isHalted, !wasLive || !newlyActive.isEmpty {
            reschedule(pollNow: true)
        }
    }

    private func removeSubscription(_ feeds: Set<Feed>) {
        for feed in feeds {
            let count = subscriptions[feed, default: 1] - 1
            subscriptions[feed] = count > 0 ? count : nil
        }
        if subscriptions.isEmpty, isRunning, !isPaused, !isHalted {
            reschedule(pollNow: false)
        }
    }

    // MARK: - Polling loop

    private func reschedule(pollNow: Bool) {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            await self?.runLoop(pollNow: pollNow)
        }
    }

    private func runLoop(pollNow: Bool) async {
        if !pollNow {
            guard await sleep(for: currentInterval) else { return }
        }
        while !Task.isCancelled {
            await poll()
            if Task.isCancelled || isHalted { return }
            guard await sleep(for: nextDelay()) else { return }
        }
    }

    private func sleep(for delay: Duration) async -> Bool {
        do {
            try await clock.sleep(for: delay)
        } catch {
            return false
        }
        historyAge = historyAge.map { $0 + delay }
        return !Task.isCancelled
    }

    private func nextDelay() -> Duration {
        let interval = currentInterval
        guard consecutiveFailures > 0 else { return interval }
        let backoff = min(interval * (1 << min(consecutiveFailures - 1, 16)), max(settings.maxBackoff, interval))
        return max(backoff, retryAfter ?? .zero)
    }

    private func dueFeeds() -> [Feed] {
        let active = Feed.background.union(subscriptions.keys)
        return Feed.allCases.filter { feed in
            guard active.contains(feed) else { return false }
            guard feed == .history else { return true }
            return historyAge.map { $0 >= settings.historyInterval } ?? true
        }
    }

    private func poll() async {
        if case .idle = state { state = .connecting }
        if needsHandshake {
            guard await handshake() else { return }
        }

        let client = client
        let plugins = snapshot.plugins
        let settings = settings
        let results = await withTaskGroup(of: (Feed, Result<SnapshotUpdate, GlancesError>).self) { group in
            for feed in dueFeeds() {
                group.addTask {
                    (feed, await Self.fetch(feed, client: client, plugins: plugins, settings: settings))
                }
            }
            var results: [(Feed, Result<SnapshotUpdate, GlancesError>)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        guard !Task.isCancelled else { return }
        apply(results)
    }

    /// Confirms Glances 5 and loads the plugin list and system information.
    private func handshake() async -> Bool {
        do throws(GlancesError) {
            let status = try await client.checkServer()
            let plugins = try await client.get(.pluginsList)
            let system = try await client.get(.system)
            guard !Task.isCancelled else { return false }
            snapshot.status = status
            snapshot.plugins = Set(plugins)
            snapshot.system = system.value
            needsHandshake = false
            return true
        } catch {
            if !Task.isCancelled { recordFailure(error) }
            return false
        }
    }

    private func apply(_ results: [(Feed, Result<SnapshotUpdate, GlancesError>)]) {
        // A failing core feed or rejected credentials make the server unusable;
        // errors of the other feeds are then only symptoms.
        for (feed, result) in results {
            if case .failure(let error) = result, feed == .core || error == .unauthorized {
                return recordFailure(error)
            }
        }
        let now = Date.now
        var next = snapshot
        for (feed, result) in results {
            switch result {
            case .success(let update):
                update(&next)
                next.updated[feed] = now
                feedErrors[feed] = nil
                if feed == .history { historyAge = .zero }
            case .failure(.cancelled):
                continue
            case .failure(let error):
                feedErrors[feed] = error
            }
        }
        snapshot = next
        consecutiveFailures = 0
        retryAfter = nil
        isStale = false
        lastSuccess = now
        transition(to: .connected)
    }

    private func recordFailure(_ error: GlancesError) {
        guard error != .cancelled else { return }
        consecutiveFailures += 1
        retryAfter = nil
        switch error {
        case .unauthorized:
            transition(to: .needsCredentials)
            needsHandshake = true
        case .unsupportedVersion(let version):
            transition(to: .unsupportedVersion(version))
            needsHandshake = true
        case .notGlances:
            transition(to: .failed(error))
            needsHandshake = true
        case .rateLimited(let after):
            transition(to: .failed(error))
            retryAfter = after
        default:
            transition(to: .failed(error))
        }
        if consecutiveFailures >= settings.staleAfterFailures {
            isStale = true
        }
    }

    @ObservationIgnored private static let logger = Logger(subsystem: "it.schnabel.MetriBar", category: "monitor")

    /// Sets `state` and logs changes. The error text may contain server
    /// details, so it stays private in the log; credentials never reach it.
    private func transition(to newState: ConnectionState) {
        guard newState != state else { return }
        state = newState
        Self.logger.notice("Server \(self.id, privacy: .public): \(String(describing: newState))")
    }

    // MARK: - Fetching

    typealias SnapshotUpdate = @Sendable (inout ServerSnapshot) -> Void

    nonisolated private static func fetch(
        _ feed: Feed, client: GlancesClient, plugins: Set<String>, settings: PollingSettings
    ) async -> Result<SnapshotUpdate, GlancesError> {
        do {
            return .success(try await update(for: feed, client: client, plugins: plugins, settings: settings))
        } catch let error as GlancesError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.transport(.unknown))
        }
    }

    nonisolated private static func update(
        for feed: Feed, client: GlancesClient, plugins: Set<String>, settings: PollingSettings
    ) async throws -> SnapshotUpdate {
        func get<Response>(_ endpoint: Endpoint<Response>, if plugin: String) async throws -> Response? {
            plugins.contains(plugin) ? try await client.get(endpoint) : nil
        }

        switch feed {
        case .core:
            async let cpu = client.get(.cpu)
            async let memory = client.get(.memory)
            async let load = client.get(.load)
            async let uptime = client.get(.uptime)
            let values = try await (cpu, memory, load, uptime)
            return {
                $0.cpu = values.0
                $0.memory = values.1
                $0.load = values.2
                $0.uptime = values.3.value
            }
        case .containers:
            let containers = try await get(.containers, if: "containers")
            return { $0.containers = containers }
        case .overview:
            async let quickLook = client.get(.quickLook)
            async let processCount = client.get(.processCount)
            async let swap = client.get(.swap)
            let values = try await (quickLook, processCount, swap)
            return {
                $0.quickLook = values.0
                $0.processCount = values.1.value
                $0.swap = values.2
            }
        case .storage:
            async let fileSystems = client.get(.fileSystems)
            async let diskIO = client.get(.diskIO)
            async let swap = client.get(.swap)
            let values = try await (fileSystems, diskIO, swap)
            return {
                $0.fileSystems = values.0
                $0.diskIO = values.1
                $0.swap = values.2
            }
        case .network:
            let network = try await client.get(.network)
            return { $0.network = network }
        case .sensors:
            async let sensors = get(.sensors, if: "sensors")
            async let gpus = get(.gpu, if: "gpu")
            let values = try await (sensors, gpus)
            return {
                $0.sensors = values.0
                $0.gpus = values.1
            }
        case .processes:
            async let processCount = client.get(.processCount)
            async let processes = client.get(.topProcesses(settings.topProcessCount))
            let values = try await (processCount, processes)
            return {
                $0.processCount = values.0.value
                $0.processes = values.1
            }
        case .alerts:
            async let alerts = client.get(.alerts)
            async let incidents = client.get(.incidents)
            let values = try await (alerts, incidents)
            return {
                $0.alerts = values.0
                $0.incidents = values.1
            }
        case .history:
            async let cpu = client.get(.history("cpu"))
            async let memory = client.get(.history("mem", field: "percent"))
            async let load = client.get(.history("load"))
            async let network = get(.history("network"), if: "network")
            let values = try await (cpu, memory, load, network)
            return {
                $0.history.cpu = values.0
                $0.history.memory = values.1
                $0.history.load = values.2
                $0.history.network = values.3
            }
        }
    }
}
