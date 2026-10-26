import Foundation

/// Sends HTTP requests. `URLSessionTransport` in the app, stubs in tests.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public static let shared = URLSessionTransport()

    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .metriBar, delegate: (any URLSessionDelegate)? = nil) {
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

extension URLSessionConfiguration {
    /// Ephemeral session without cookies or caches. Waits briefly for
    /// connectivity, which also covers the local network privacy prompt.
    public static var metriBar: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return configuration
    }
}
