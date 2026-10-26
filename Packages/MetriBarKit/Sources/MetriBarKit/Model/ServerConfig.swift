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

    public init(id: UUID = UUID(), name: String = "", url: URL, username: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.isEnabled = isEnabled
    }

    public var displayName: String {
        name.isEmpty ? (url.host() ?? url.absoluteString) : name
    }
}
