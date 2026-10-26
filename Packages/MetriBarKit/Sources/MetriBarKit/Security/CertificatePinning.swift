import CryptoKit
import Foundation
import Security
import Synchronization

/// SHA-256 fingerprint of a DER-encoded certificate, written like browsers
/// and `openssl x509 -fingerprint -sha256` show it: `AB:CD:…`.
public struct CertificateFingerprint: Sendable, Hashable, CustomStringConvertible {
    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == SHA256.byteCount else { return nil }
        self.bytes = bytes
    }

    /// Accepts hex digits with or without `:`, `-` or space separators.
    public init?(_ text: String) {
        let hex = text.filter { !":- ".contains($0) }
        guard hex.count == SHA256.byteCount * 2, hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes = Data(capacity: SHA256.byteCount)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.bytes = bytes
    }

    public init(certificate: SecCertificate) {
        bytes = Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
    }

    public var description: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

extension CertificateFingerprint: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let fingerprint = CertificateFingerprint(text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid fingerprint"))
        }
        self = fingerprint
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Thrown by `URLSessionTransport` when a server presents a certificate
/// other than the pinned one.
enum CertificatePinningError: Error {
    case mismatch(presented: CertificateFingerprint)
}

/// Accepts exactly the pinned certificate, even if it is self-signed or not
/// trusted by the system, and rejects every other certificate.
final class PinningTaskDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let expected: CertificateFingerprint
    private let presented = Mutex<CertificateFingerprint?>(nil)

    init(expected: CertificateFingerprint) {
        self.expected = expected
    }

    /// The fingerprint of a rejected certificate, if any.
    var mismatch: CertificateFingerprint? {
        presented.withLock { $0 }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        else {
            return (.performDefaultHandling, nil)
        }
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            return (.cancelAuthenticationChallenge, nil)
        }
        let fingerprint = CertificateFingerprint(certificate: leaf)
        guard fingerprint == expected else {
            presented.withLock { $0 = fingerprint }
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}

/// The certificate a server presents, read before trusting it.
public struct CertificateInfo: Sendable, Equatable {
    public var fingerprint: CertificateFingerprint
    /// Subject summary, usually the common name.
    public var subject: String?
    /// Whether the system trusts the certificate for this host without a pin.
    public var isTrustedBySystem: Bool
}

public enum CertificateInspector {
    /// Connects to `baseURL`, reads the server certificate and aborts the
    /// TLS handshake before any request, so no credentials are sent.
    public static func inspect(
        _ baseURL: URL, configuration: URLSessionConfiguration = .metriBar
    ) async throws(GlancesError) -> CertificateInfo {
        guard baseURL.scheme?.lowercased() == "https" else { throw .transport(.unsupportedURL) }
        let delegate = InspectingTaskDelegate()
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            _ = try await session.data(for: URLRequest(url: baseURL.appending(path: "status")), delegate: delegate)
        } catch let error as URLError {
            guard let info = delegate.info else { throw .transport(error.code) }
            return info
        } catch {
            guard let info = delegate.info else { throw .transport(.unknown) }
            return info
        }
        guard let info = delegate.info else { throw .transport(.unknown) }
        return info
    }
}

private final class InspectingTaskDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let captured = Mutex<CertificateInfo?>(nil)

    var info: CertificateInfo? {
        captured.withLock { $0 }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        else {
            return (.cancelAuthenticationChallenge, nil)
        }
        let info = CertificateInfo(
            fingerprint: CertificateFingerprint(certificate: leaf),
            subject: SecCertificateCopySubjectSummary(leaf) as String?,
            isTrustedBySystem: SecTrustEvaluateWithError(trust, nil)
        )
        captured.withLock { $0 = info }
        return (.cancelAuthenticationChallenge, nil)
    }
}
