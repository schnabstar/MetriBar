import Foundation
import Security
import Synchronization

/// Stores server passwords. Passwords never go into `ServerConfig`,
/// UserDefaults, logs or exports.
public protocol CredentialStore: Sendable {
    func password(for serverID: UUID) throws(CredentialStoreError) -> String?
    func setPassword(_ password: String, for serverID: UUID) throws(CredentialStoreError)
    func removePassword(for serverID: UUID) throws(CredentialStoreError)
}

public enum CredentialStoreError: Error, Sendable, Equatable {
    case keychain(OSStatus)
    case invalidData
}

/// Generic password items in the login keychain, one per server.
///
/// Uses the file-based keychain rather than the data protection keychain,
/// which would require an `application-identifier` entitlement and thus a
/// provisioning profile. Access is bound to the app's code signature.
public struct KeychainCredentialStore: CredentialStore {
    public static let defaultService = "it.schnabel.MetriBar.server"

    private let service: String

    public init(service: String = Self.defaultService) {
        self.service = service
    }

    public func password(for serverID: UUID) throws(CredentialStoreError) -> String? {
        var query = baseQuery(serverID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
                throw .invalidData
            }
            return password
        case errSecItemNotFound:
            return nil
        default:
            throw .keychain(status)
        }
    }

    public func setPassword(_ password: String, for serverID: UUID) throws(CredentialStoreError) {
        let data = Data(password.utf8)
        let status = SecItemUpdate(baseQuery(serverID) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery(serverID)
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "MetriBar server password"
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw .keychain(addStatus) }
        default:
            throw .keychain(status)
        }
    }

    public func removePassword(for serverID: UUID) throws(CredentialStoreError) {
        let status = SecItemDelete(baseQuery(serverID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status) }
    }

    private func baseQuery(_ serverID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID.uuidString,
        ]
    }
}

/// Keeps passwords in memory, for tests and previews.
public final class InMemoryCredentialStore: CredentialStore {
    private let passwords = Mutex<[UUID: String]>([:])

    public init(_ passwords: [UUID: String] = [:]) {
        self.passwords.withLock { $0 = passwords }
    }

    public func password(for serverID: UUID) throws(CredentialStoreError) -> String? {
        passwords.withLock { $0[serverID] }
    }

    public func setPassword(_ password: String, for serverID: UUID) throws(CredentialStoreError) {
        passwords.withLock { $0[serverID] = password }
    }

    public func removePassword(for serverID: UUID) throws(CredentialStoreError) {
        _ = passwords.withLock { $0.removeValue(forKey: serverID) }
    }
}
