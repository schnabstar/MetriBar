import Foundation

/// Looks at all monitors every few seconds and hands the notices that
/// `AlertEvaluator` produces to `deliver`.
///
/// It works from the timer, not from the monitors' updates, so that time
/// passing is noticed also when a server stopped answering or polling was
/// halted.
@MainActor
public final class AlertCenter {
    public static let interval: Duration = .seconds(15)

    private var evaluator: AlertEvaluator
    private let clock: any Clock<Duration>
    private let now: @MainActor () -> Date
    private let monitors: @MainActor () -> [ServerMonitor]
    private let deliver: @MainActor ([AlertNotice]) -> Void
    private var loop: Task<Void, Never>?

    public init(
        settings: NotificationSettings = NotificationSettings(),
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @MainActor () -> Date = { Date() },
        monitors: @escaping @MainActor () -> [ServerMonitor],
        deliver: @escaping @MainActor ([AlertNotice]) -> Void
    ) {
        evaluator = AlertEvaluator(settings: settings)
        self.clock = clock
        self.now = now
        self.monitors = monitors
        self.deliver = deliver
    }

    public var isRunning: Bool {
        loop != nil
    }

    /// Applies new settings and starts or stops the loop. Turning
    /// notifications off forgets what was pending.
    public func update(settings: NotificationSettings) {
        let wasEnabled = evaluator.settings.isEnabled
        evaluator.settings = settings
        if settings.isEnabled {
            start()
        } else {
            stop()
            if wasEnabled { evaluator = AlertEvaluator(settings: settings) }
        }
    }

    public func start() {
        guard loop == nil, evaluator.settings.isEnabled else { return }
        let clock = clock
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.evaluate()
                do {
                    try await clock.sleep(for: Self.interval)
                } catch {
                    return
                }
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func handle(_ event: SystemEvent) {
        switch event {
        case .didWake, .networkChanged: evaluator.noteResume(now: now())
        case .willSleep: break
        }
    }

    /// One look at all servers.
    public func evaluate() {
        let date = now()
        let candidates = monitors().filter { $0.config.isEnabled && $0.config.notificationsEnabled }
        evaluator.forget(except: Set(candidates.map(\.id)))

        var notices: [AlertNotice] = []
        for monitor in candidates {
            let isOffline: Bool
            switch monitor.health {
            case .unknown: continue
            case .offline: isOffline = true
            case .ok, .warning, .critical: isOffline = false
            }
            let watched = monitor.watchedConditions(now: date)
            let observation = ServerObservation(
                serverID: monitor.id, serverName: monitor.displayName, isOffline: isOffline,
                conditions: isOffline ? [] : watched.conditions + monitor.ruleConditions,
                unavailable: watched.unavailable)
            notices += evaluator.evaluate(observation, now: date)
        }
        if !notices.isEmpty { deliver(notices) }
    }
}
