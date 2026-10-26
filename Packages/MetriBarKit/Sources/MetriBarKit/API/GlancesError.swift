import Foundation

public enum GlancesError: Error, Sendable, Equatable {
    /// The request did not reach the server or the connection failed,
    /// including TLS and App Transport Security errors.
    case transport(URLError.Code)
    /// The server presented a certificate other than the pinned one. Either
    /// the certificate was renewed or someone intercepts the connection.
    case certificateMismatch(presented: CertificateFingerprint)
    /// The task was cancelled, for example because polling stopped.
    case cancelled
    /// `400`: Glances rejects the `Host` header (DNS rebinding protection)
    /// unless the host is listed in `webui_allowed_hosts`.
    case badRequest(detail: String?)
    /// `401`: missing or wrong credentials.
    case unauthorized
    /// `404`: unknown plugin or field, or no Glances at this URL.
    case notFound(detail: String?)
    /// `429`: too many failed logins (or requests) from this client.
    case rateLimited(retryAfter: Duration?)
    case http(status: Int, detail: String?)
    /// The response is not from a Glances server.
    case notGlances
    /// A Glances server with an API other than version 5.
    case unsupportedVersion(String)
    /// The response could not be decoded. The message names the coding
    /// path, never the response content.
    case decoding(String)
}

/// Error body of FastAPI: `{"detail": "Plugin 'gpu' not found"}`.
struct ErrorBody: Decodable {
    var detail: String?

    /// The detail message, shortened so that a misbehaving server cannot
    /// flood the UI.
    static func detail(from data: Data) -> String? {
        guard let detail = try? JSONDecoder().decode(ErrorBody.self, from: data).detail else { return nil }
        return String(detail.prefix(200))
    }
}

extension DecodingError {
    /// A description without the decoded values, safe for logs and the UI.
    var safeDescription: String {
        func path(_ context: Context) -> String {
            let path = context.codingPath.map { key in
                key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)"
            }
            let joined = path.joined().trimmingPrefix(".")
            return joined.isEmpty ? "top level" : String(joined)
        }
        switch self {
        case .typeMismatch(let type, let context):
            return "Unexpected type at \(path(context)), expected \(type)"
        case .valueNotFound(let type, let context):
            return "Missing value at \(path(context)), expected \(type)"
        case .keyNotFound(let key, let context):
            return "Missing key \(key.stringValue) at \(path(context))"
        case .dataCorrupted(let context):
            return "Invalid JSON at \(path(context))"
        @unknown default:
            return "Invalid response"
        }
    }
}
