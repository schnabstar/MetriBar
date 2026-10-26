import Foundation
import Network

/// How well a server URL protects the connection, for warnings in the UI.
public enum TransportSecurity: Sendable, Equatable {
    case encrypted
    /// Plain HTTP. `localNetwork` is `true` for loopback, private and
    /// link-local addresses and for names that are local by convention
    /// (`.local`, single-label names, …). It is a hint for the wording, not
    /// a guarantee: a local name can still resolve to a public address.
    case unencrypted(localNetwork: Bool)

    public init(url: URL) {
        if url.scheme?.lowercased() == "https" {
            self = .encrypted
        } else {
            self = .unencrypted(localNetwork: Self.isLocal(host: url.host(percentEncoded: false) ?? ""))
        }
    }

    private static let localSuffixes = [
        ".local", ".lan", ".home", ".home.arpa", ".internal", ".localdomain", ".fritz.box",
    ]

    static func isLocal(host rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !host.isEmpty else { return false }
        if let address = IPv4Address(host) {
            return isLocal(address)
        }
        if let address = IPv6Address(host) {
            return isLocal(address)
        }
        if host == "localhost" || !host.contains(".") {
            return true
        }
        return localSuffixes.contains { host.hasSuffix($0) }
    }

    private static func isLocal(_ address: IPv4Address) -> Bool {
        let bytes = [UInt8](address.rawValue)
        switch (bytes[0], bytes[1]) {
        case (10, _), (127, _): return true
        case (172, 16...31): return true
        case (192, 168): return true
        case (169, 254): return true
        case (100, 64...127): return true  // carrier-grade NAT, used by Tailscale
        default: return false
        }
    }

    private static func isLocal(_ address: IPv6Address) -> Bool {
        let bytes = [UInt8](address.rawValue)
        if address.isLoopback || address.isLinkLocal { return true }
        return bytes[0] & 0xfe == 0xfc  // unique local fc00::/7
    }
}
