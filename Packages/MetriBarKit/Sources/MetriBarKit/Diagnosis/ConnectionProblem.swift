import Foundation

/// What went wrong, in terms the UI can explain and offer a fix for.
public enum ConnectionProblem: Sendable, Equatable {
    case hostNotFound
    /// Nothing listens on the port: Glances is not running, listens on
    /// 127.0.0.1 only (the Glances 5 default) or uses another port.
    case connectionRefused
    case timedOut
    /// macOS blocks the connection because MetriBar lacks the local network
    /// permission.
    case localNetworkDenied
    case offline
    /// The TLS handshake failed, for example HTTPS to a plain HTTP port.
    case tlsHandshakeFailed
    /// The certificate is self-signed, expired or for another host.
    case untrustedCertificate
    case certificateMismatch(presented: CertificateFingerprint)
    /// App Transport Security blocked plain HTTP.
    case insecureConnectionBlocked
    /// Glances rejected the `Host` header (`webui_allowed_hosts`).
    case hostRejected
    case unauthorized
    case rateLimited(retryAfter: Duration?)
    case notGlances
    case glances4
    case unsupportedVersion(String)
    case serverError(status: Int)
    case invalidResponse
    case other(String)

    public init(_ error: GlancesError) {
        switch error {
        case .transport(let code):
            self = Self.problem(for: code)
        case .certificateMismatch(let presented):
            self = .certificateMismatch(presented: presented)
        case .cancelled:
            self = .other("cancelled")
        case .badRequest:
            self = .hostRejected
        case .unauthorized:
            self = .unauthorized
        case .notFound:
            self = .serverError(status: 404)
        case .rateLimited(let retryAfter):
            self = .rateLimited(retryAfter: retryAfter)
        case .http(let status, _):
            self = .serverError(status: status)
        case .notGlances:
            self = .notGlances
        case .unsupportedVersion(let version):
            self = version.hasPrefix("4") ? .glances4 : .unsupportedVersion(version)
        case .decoding:
            self = .invalidResponse
        }
    }

    public init(_ state: ConnectionState) {
        switch state {
        case .needsCredentials: self = .unauthorized
        case .unsupportedVersion(let version): self.init(GlancesError.unsupportedVersion(version))
        case .failed(let error): self.init(error)
        case .idle, .connecting, .connected: self = .other("\(state)")
        }
    }

    private static func problem(for code: URLError.Code) -> ConnectionProblem {
        switch code {
        case .cannotFindHost, .dnsLookupFailed:
            .hostNotFound
        case .cannotConnectToHost:
            .connectionRefused
        case .timedOut:
            .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            .offline
        case .secureConnectionFailed:
            .tlsHandshakeFailed
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateHasBadDate,
            .serverCertificateNotYetValid:
            .untrustedCertificate
        case .appTransportSecurityRequiresSecureConnection:
            .insecureConnectionBlocked
        default:
            .other("URLError \(code.rawValue)")
        }
    }

    /// Problems that missing local network permission can cause. Check with
    /// `LocalNetworkCheck` before blaming the server.
    public var mayBeLocalNetworkPermission: Bool {
        switch self {
        case .timedOut, .connectionRefused, .offline: true
        default: false
        }
    }
}
