import Foundation
import Network
import Synchronization

public enum LocalNetworkCheck {
    /// Settings pane where the user grants the permission.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork")!

    /// Whether macOS blocks connections from MetriBar to the server because
    /// the local network permission is missing: `true` if blocked, `false`
    /// if a connection works, `nil` if that cannot be determined in time.
    ///
    /// URLSession only reports a timeout in this case; the Network
    /// framework reports the reason.
    public static func isDenied(for url: URL, timeout: Duration = .seconds(3)) async -> Bool? {
        guard let host = url.host(percentEncoded: false),
            let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? (url.scheme == "https" ? 443 : 80)))
        else { return nil }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let once = Once()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            let finish: @Sendable (Bool?) -> Void = { result in
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(false)
                case .waiting, .failed:
                    if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        finish(true)
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            Task {
                try? await Task.sleep(for: timeout)
                finish(nil)
            }
        }
    }

    private final class Once: Sendable {
        private let done = Mutex(false)

        /// Returns `true` exactly once.
        func claim() -> Bool {
            done.withLock { done in
                defer { done = true }
                return !done
            }
        }
    }
}
