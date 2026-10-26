import Foundation

/// Sends HTTP requests. `URLSessionTransport` in the app, stubs in tests.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public static let shared = URLSessionTransport()

    private let session: URLSession
    private let pinnedCertificate: CertificateFingerprint?

    /// - Parameter pinnedCertificate: Accept exactly this certificate, for
    ///   servers with a self-signed certificate. Without a pin the system
    ///   validates the certificate as usual.
    public init(configuration: URLSessionConfiguration = .metriBar, pinnedCertificate: CertificateFingerprint? = nil) {
        session = URLSession(configuration: configuration)
        self.pinnedCertificate = pinnedCertificate
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let pinnedCertificate else {
            return try await session.data(for: request)
        }
        let delegate = PinningTaskDelegate(expected: pinnedCertificate)
        do {
            return try await session.data(for: request, delegate: delegate)
        } catch {
            if let presented = delegate.mismatch {
                throw CertificatePinningError.mismatch(presented: presented)
            }
            throw error
        }
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
