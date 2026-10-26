import AppKit
import Network
import Synchronization

public enum SystemEvent: Sendable, Equatable {
    case willSleep
    case didWake
    /// The network path changed, for example after switching Wi-Fi networks
    /// or connecting a VPN.
    case networkChanged
}

/// Reports sleep, wake and network changes on the main actor.
@MainActor
public final class SystemEventObserver {
    private var tokens: [any NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?

    public init() {}

    public func start(_ handler: @escaping @MainActor (SystemEvent) -> Void) {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        let observed: [(Notification.Name, SystemEvent)] = [
            (NSWorkspace.willSleepNotification, .willSleep),
            (NSWorkspace.didWakeNotification, .didWake),
        ]
        for (name, event) in observed {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(event) }
            }
            tokens.append(token)
        }

        // The first update reports the current path; only changes matter.
        let lastPath = Mutex<String?>(nil)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let signature = "\(path.status) \(path.availableInterfaces.map(\.name).sorted())"
            let changed = lastPath.withLock { last in
                defer { last = signature }
                return last != nil && last != signature
            }
            guard changed else { return }
            MainActor.assumeIsolated { handler(.networkChanged) }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens {
            center.removeObserver(token)
        }
        tokens = []
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}
