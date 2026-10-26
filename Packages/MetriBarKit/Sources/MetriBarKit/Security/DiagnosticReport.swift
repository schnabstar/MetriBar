import Foundation

/// Text the user can copy to describe a connection problem, for example in
/// a GitHub issue. Contains no passwords, user names, process command lines
/// or monitored values, and hides the host unless asked to include it.
@MainActor
public enum DiagnosticReport {
    public static func make(
        for monitor: ServerMonitor,
        includeHost: Bool,
        appVersion: String,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) -> String {
        let config = monitor.config
        let snapshot = monitor.snapshot
        var lines = [
            "MetriBar \(appVersion) on macOS \(osVersion)",
            "Server: \(redacted(config.url, includeHost: includeHost))",
            "Encryption: \(describe(config.transportSecurity))",
            "Pinned certificate: \(config.pinnedCertificate == nil ? "no" : "yes")",
            "Authentication: \(config.username == nil ? "no" : "yes")",
            "Glances: \(snapshot.status?.glancesVersion ?? "unknown") (API \(snapshot.status?.version ?? "unknown"))",
            "State: \(describe(monitor.state))",
            "Consecutive failures: \(monitor.consecutiveFailures), stale: \(monitor.isStale ? "yes" : "no")",
            "Last success: \(monitor.lastSuccess.map { $0.formatted(.iso8601) } ?? "never")",
            "Plugins: \(snapshot.plugins.isEmpty ? "unknown" : snapshot.plugins.sorted().joined(separator: ", "))",
        ]
        let feedErrors = monitor.feedErrors.map { "\($0.key): \($0.value)" }.sorted()
        if !feedErrors.isEmpty {
            lines.append("Feed errors: \(feedErrors.joined(separator: "; "))")
        }
        var report = lines.joined(separator: "\n")
        // Error details from the server may repeat the host name.
        if !includeHost, let host = config.url.host(percentEncoded: false), !host.isEmpty {
            report = report.replacingOccurrences(of: host, with: "<host>", options: .caseInsensitive)
        }
        return report
    }

    /// Scheme, host (or `<host>`), port and path; never user, password,
    /// query or fragment.
    public static func redacted(_ url: URL, includeHost: Bool) -> String {
        let scheme = url.scheme ?? "?"
        let host = includeHost ? (url.host(percentEncoded: false) ?? "?") : "<host>"
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)\(url.path(percentEncoded: false))"
    }

    private static func describe(_ security: TransportSecurity) -> String {
        switch security {
        case .encrypted: "HTTPS"
        case .unencrypted(localNetwork: true): "HTTP (local network)"
        case .unencrypted(localNetwork: false): "HTTP"
        }
    }

    private static func describe(_ state: ConnectionState) -> String {
        switch state {
        case .idle: "idle"
        case .connecting: "connecting"
        case .connected: "connected"
        case .failed(let error): "failed: \(error)"
        case .needsCredentials: "credentials rejected (401)"
        case .unsupportedVersion(let version): "unsupported Glances version \(version)"
        }
    }
}
