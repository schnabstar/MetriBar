import Foundation

/// A configured Glances server. Contains no secrets: the password lives in
/// the Keychain under the server's `id`.
public struct ServerConfig: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    /// Display name; empty to use the host name.
    public var name: String
    public var url: URL
    /// User name for HTTP Basic auth, `nil` when the server has no password.
    public var username: String?
    public var isEnabled: Bool
    /// Certificate accepted for this server even if the system does not
    /// trust it, for self-signed certificates. Not a secret.
    public var pinnedCertificate: CertificateFingerprint?

    public init(
        id: UUID = UUID(),
        name: String = "",
        url: URL,
        username: String? = nil,
        isEnabled: Bool = true,
        pinnedCertificate: CertificateFingerprint? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.isEnabled = isEnabled
        self.pinnedCertificate = pinnedCertificate
    }

    public var displayName: String {
        name.isEmpty ? (url.host() ?? url.absoluteString) : name
    }

    public var transportSecurity: TransportSecurity {
        TransportSecurity(url: url)
    }

    /// The password would travel unencrypted: warn before saving it.
    public var sendsPasswordUnencrypted: Bool {
        username != nil && transportSecurity != .encrypted
    }
}
