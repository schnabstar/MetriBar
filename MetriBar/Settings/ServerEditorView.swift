import MetriBarKit
import SwiftUI

/// The values of the editor form before they are saved.
struct ServerDraft: Equatable {
    var id = UUID()
    var name = ""
    var urlText = ""
    var requiresPassword = false
    var username = "glances"
    /// Typed password; only used when `passwordEdited` is set.
    var password = ""
    var passwordEdited = false
    var isEnabled = true
    var pinnedCertificate: CertificateFingerprint?

    init() {}

    init(config: ServerConfig) {
        id = config.id
        name = config.name
        urlText = config.url.absoluteString
        requiresPassword = config.username != nil
        username = config.username ?? "glances"
        isEnabled = config.isEnabled
        pinnedCertificate = config.pinnedCertificate
    }

    var url: Result<URL, ServerURLError> {
        Result { () throws(ServerURLError) in try ServerURL.parse(urlText) }
    }

    func makeConfig() throws(ServerURLError) -> ServerConfig {
        let url = try ServerURL.parse(urlText)
        let trimmedUser = username.trimmingCharacters(in: .whitespaces)
        return ServerConfig(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            url: url,
            username: requiresPassword ? (trimmedUser.isEmpty ? "glances" : trimmedUser) : nil,
            isEnabled: isEnabled,
            pinnedCertificate: url.scheme == "https" ? pinnedCertificate : nil
        )
    }

    var passwordChange: PasswordChange {
        guard requiresPassword else { return .remove }
        guard passwordEdited else { return .keep }
        return password.isEmpty ? .remove : .set(password)
    }
}

struct ServerEditorView: View {
    enum Mode: Equatable {
        case add
        case edit(UUID)
    }

    let mode: Mode
    var onFinish: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var draft = ServerDraft()
    @State private var original = ServerDraft()
    @State private var hasStoredPassword = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                serverSection
                authenticationSection
                if case .success(let url) = draft.url, url.scheme == "https" {
                    CertificateSection(url: url, pinned: $draft.pinnedCertificate)
                }
                ConnectionTestSection(draft: draft, hasStoredPassword: hasStoredPassword)
            }
            .formStyle(.grouped)

            Divider()
            buttons
                .padding(12)
        }
        .onAppear(perform: load)
        .alert("Could Not Save", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: Sections

    private var serverSection: some View {
        Section {
            TextField("URL", text: $draft.urlText, prompt: Text(verbatim: "http://raspberrypi.local:61208"))
                .textContentType(.URL)
                .autocorrectionDisabled()
            if let message = urlMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            TextField("Name", text: $draft.name, prompt: Text("Host name"))
            if case .edit = mode {
                Toggle("Monitor this server", isOn: $draft.isEnabled)
            }
        } header: {
            Text(mode == .add ? "New Server" : "Server")
        } footer: {
            Text("The address of Glances 5 running as a web server (glances -s), including the port.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var authenticationSection: some View {
        Section("Authentication") {
            Toggle("Server requires a password", isOn: $draft.requiresPassword)
            if draft.requiresPassword {
                TextField("User name", text: $draft.username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                SecureField(
                    "Password", text: $draft.password,
                    prompt: Text(hasStoredPassword && !draft.passwordEdited ? "Saved in Keychain" : "Required")
                )
                .textContentType(.password)
                .onChange(of: draft.password) { draft.passwordEdited = true }
            }
            if case .success(let url) = draft.url {
                encryptionNote(TransportSecurity(url: url))
            }
        }
    }

    @ViewBuilder
    private func encryptionNote(_ security: TransportSecurity) -> some View {
        switch security {
        case .encrypted:
            Label("Encrypted connection (HTTPS)", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unencrypted(let localNetwork):
            if draft.requiresPassword {
                Label(
                    "The password is sent unencrypted and can be read by others on the network. Use HTTPS, for example with a reverse proxy.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Label(
                    localNetwork ? "Unencrypted connection (local network)" : "Unencrypted connection",
                    systemImage: "lock.open"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var buttons: some View {
        HStack {
            if mode == .add {
                Button("Cancel", role: .cancel) { onFinish?() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Server", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            } else {
                Spacer()
                Button("Revert") { draft = original }
                    .disabled(draft == original)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == original || !isValid)
            }
        }
    }

    // MARK: Logic

    private var isValid: Bool {
        if case .success = draft.url { return true }
        return false
    }

    private var urlMessage: String? {
        guard !draft.urlText.trimmingCharacters(in: .whitespaces).isEmpty,
            case .failure(let error) = draft.url
        else { return nil }
        switch error {
        case .empty: return nil
        case .unsupportedScheme(let scheme):
            return String(localized: "Use http:// or https:// instead of \(scheme)://.")
        case .missingHost: return String(localized: "The URL needs a host name or IP address.")
        case .containsCredentials:
            return String(localized: "Enter user name and password below, not in the URL.")
        case .invalid: return String(localized: "This is not a valid URL.")
        }
    }

    private func load() {
        guard case .edit(let id) = mode, let config = model.server(id) else { return }
        draft = ServerDraft(config: config)
        original = draft
        hasStoredPassword = model.hasPassword(for: id)
    }

    private func save() {
        do {
            let config = try draft.makeConfig()
            try model.save(config, password: draft.passwordChange)
            hasStoredPassword = model.hasPassword(for: config.id)
            draft = ServerDraft(config: config)
            original = draft
            if mode == .add {
                model.editingServerID = config.id
                model.selectedServerID = config.id
                onFinish?()
            }
        } catch let error as CredentialStoreError {
            saveError = message(for: error)
        } catch {
            saveError = String(localized: "The URL is not valid.")
        }
    }

    private func message(for error: CredentialStoreError) -> String {
        switch error {
        case .missingEntitlement:
            String(
                localized: "This build of MetriBar cannot use the Keychain. See the build instructions in the README.")
        case .keychain(let status):
            String(localized: "The Keychain reported error \(Int(status)).")
        case .invalidData:
            String(localized: "The saved password could not be read.")
        }
    }
}
