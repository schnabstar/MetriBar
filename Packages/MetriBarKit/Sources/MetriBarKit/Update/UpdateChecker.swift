import Foundation

public enum UpdateError: Error, Sendable, Equatable {
    /// No connection, timeout or TLS failure.
    case network
    /// GitHub's limit for anonymous requests is used up; `until` is when it
    /// resets, if GitHub said so.
    case rateLimited(until: Date?)
    /// The repository has no published release.
    case notFound
    /// The answer was not what the GitHub API documents.
    case invalidResponse
}

public enum UpdateResult: Sendable, Equatable {
    /// The installed version is the newest regular release (or newer).
    case upToDate
    case available(AvailableUpdate)
    case failed(UpdateError)
}

/// Asks GitHub whether a newer regular release of MetriBar exists.
///
/// Sends one anonymous `GET` request and nothing else: no identifier, no
/// cookies, no information about the servers. GitHub sees the IP address,
/// like with any download.
public struct UpdateChecker: Sendable {
    public static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/schnabstar/MetriBar/releases/latest")!

    private let currentVersion: AppVersion
    private let transport: any HTTPTransport
    private let endpoint: URL

    public init(
        currentVersion: AppVersion,
        transport: any HTTPTransport = URLSessionTransport(configuration: .metriBarConnectionTest),
        endpoint: URL = UpdateChecker.latestReleaseURL
    ) {
        self.currentVersion = currentVersion
        self.transport = transport
        self.endpoint = endpoint
    }

    public func check(now: Date = Date()) async -> UpdateResult {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub requires a User-Agent; this one names only the app.
        request.setValue("MetriBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            return .failed(.network)
        }
        guard let http = response as? HTTPURLResponse else { return .failed(.invalidResponse) }

        switch http.statusCode {
        case 200:
            break
        case 404:
            return .failed(.notFound)
        case 403, 429:
            return .failed(.rateLimited(until: Self.resetDate(of: http, now: now)))
        default:
            return .failed(.invalidResponse)
        }

        guard let release = try? JSONDecoder().decode(ReleaseInfo.self, from: data),
            let update = AvailableUpdate(release)
        else { return .failed(.invalidResponse) }

        guard release.isRegularRelease, update.appVersion > currentVersion else { return .upToDate }
        return .available(update)
    }

    private static func resetDate(of response: HTTPURLResponse, now: Date) -> Date? {
        if let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) {
            return now.addingTimeInterval(retry)
        }
        return response.value(forHTTPHeaderField: "X-RateLimit-Reset")
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
    }
}

/// When the automatic check runs.
public enum UpdatePolicy {
    /// At most once a day.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// `true` if no check happened yet, the last one is a day old, or the
    /// clock was set back. A failed check counts as a check, so a broken
    /// connection does not lead to repeated requests.
    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let lastCheck else { return true }
        return lastCheck > now || now.timeIntervalSince(lastCheck) >= interval
    }
}
