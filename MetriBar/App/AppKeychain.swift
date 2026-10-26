import MetriBarKit

enum AppKeychain {
    /// Official builds use the data protection keychain. Builds without a
    /// provisioning profile opt into the file-based keychain through
    /// `METRIBAR_FILE_KEYCHAIN` (see Config/Local.xcconfig.example).
    static let store: any CredentialStore = {
        #if METRIBAR_FILE_KEYCHAIN
            KeychainCredentialStore(keychain: .fileBased)
        #else
            KeychainCredentialStore(keychain: .dataProtection)
        #endif
    }()
}
