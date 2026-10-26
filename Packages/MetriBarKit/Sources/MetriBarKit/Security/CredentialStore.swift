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
    /// The build lacks the keychain access group entitlement, usually
    /// because it was signed without a provisioning profile.
    case missingEntitlement
    case keychain(OSStatus)
    case invalidData
}

/// Generic password items in the keychain, one per server.
public struct KeychainCredentialStore: CredentialStore {
    public enum Keychain: Sendable {
        /// The data protection keychain (Apple's recommendation, see
        /// TN3137). Access is bound to the keychain access group, that is to
        /// team and bundle identifier, and requires a provisioning profile.
        case dataProtection
        /// The file-based login keychain, for builds without a provisioning
        /// profile. Access is bound to the code signature, so a build signed
        /// differently asks for permission.
        case fileBased
    }

    public static let defaultService = "it.schnabel.MetriBar.server"

    private let service: String
    private let keychain: Keychain

    public init(service: String = Self.defaultService, keychain: Keychain = .dataProtection) {
        self.service = service
        self.keychain = keychain
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
            throw Self.error(for: status)
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
            if keychain == .dataProtection {
                // Never synced or restored to another Mac.
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Self.error(for: addStatus) }
        default:
            throw Self.error(for: status)
        }
    }

    public func removePassword(for serverID: UUID) throws(CredentialStoreError) {
        let status = SecItemDelete(baseQuery(serverID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(for: status) }
    }

    private func baseQuery(_ serverID: UUID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID.uuidString,
        ]
        if keychain == .dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private static func error(for status: OSStatus) -> CredentialStoreError {
        status == errSecMissingEntitlement ? .missingEntitlement : .keychain(status)
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
