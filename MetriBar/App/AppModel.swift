import Foundation
import MetriBarKit
import Observation

enum SettingsTab: String, Hashable {
    case servers, display, general
}

/// How a password changes when a server is saved.
enum PasswordChange: Equatable {
    case keep
    case set(String)
    case remove
}

/// App-wide state: the server list, preferences and the monitors.
@MainActor
@Observable
final class AppModel {
    let center: MonitorCenter
    private(set) var servers: [ServerConfig] = []
    private(set) var preferences: Preferences

    /// Server shown in the popover and the dashboard.
    var selectedServerID: UUID? {
        didSet { defaults.set(selectedServerID?.uuidString, forKey: Keys.selectedServer) }
    }

    /// Navigation state of the settings window.
    var settingsTab: SettingsTab = .servers
    var editingServerID: UUID?
    var isAddingServer = false

    /// Section shown in the dashboard window.
    var dashboardSection: DashboardSection = .overview

    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let credentials: any CredentialStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let events = SystemEventObserver()

    private enum Keys {
        static let preferences = "preferences"
        static let selectedServer = "selectedServer"
    }

    init(
        configStore: ConfigStore = ConfigStore(),
        credentials: any CredentialStore = AppKeychain.store,
        defaults: UserDefaults = .standard,
        observeSystemEvents: Bool = true
    ) {
        self.configStore = configStore
        self.credentials = credentials
        self.defaults = defaults
        let preferences =
            defaults.data(forKey: Keys.preferences)
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        self.preferences = preferences
        selectedServerID = defaults.string(forKey: Keys.selectedServer).flatMap(UUID.init(uuidString:))
        center = MonitorCenter(settings: preferences.pollingSettings) { [credentials] config in
            Self.makeClient(for: config, credentials: credentials)
        }
        servers = configStore.load()
        center.apply(servers)
        if observeSystemEvents {
            events.start { [weak self] event in self?.center.handle(event) }
        }
    }

    // MARK: - Selection

    var selectedMonitor: ServerMonitor? {
        selectedServerID.flatMap(center.monitor(for:))
            ?? center.monitors.first { $0.config.isEnabled }
            ?? center.monitors.first
    }

    var menuBarMonitor: ServerMonitor? {
        preferences.menuBarServerID.flatMap(center.monitor(for:)) ?? selectedMonitor
    }

    // MARK: - Preferences

    func update(_ change: (inout Preferences) -> Void) {
        var next = preferences
        change(&next)
        guard next != preferences else { return }
        let pollingChanged = next.pollingSettings != preferences.pollingSettings
        preferences = next
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Keys.preferences)
        }
        if pollingChanged {
            center.update(settings: next.pollingSettings)
        }
    }

    // MARK: - Servers

    func server(_ id: UUID) -> ServerConfig? {
        servers.first { $0.id == id }
    }

    func hasPassword(for id: UUID) -> Bool {
        ((try? credentials.password(for: id)) ?? nil) != nil
    }

    func password(for id: UUID) -> String? {
        (try? credentials.password(for: id)) ?? nil
    }

    /// Adds or updates a server. The password is stored first so the
    /// monitor starts with the right credentials.
    func save(_ config: ServerConfig, password: PasswordChange) throws(CredentialStoreError) {
        switch password {
        case .keep: break
        case .set(let value): try credentials.setPassword(value, for: config.id)
        case .remove: try credentials.removePassword(for: config.id)
        }

        if let index = servers.firstIndex(where: { $0.id == config.id }) {
            let configChanged = servers[index] != config
            servers[index] = config
            persist()
            if !configChanged, password != .keep {
                center.reconnect(config.id)
            }
        } else {
            servers.append(config)
            persist()
            if selectedServerID == nil { selectedServerID = config.id }
        }
    }

    func remove(_ id: UUID) {
        try? credentials.removePassword(for: id)
        servers.removeAll { $0.id == id }
        if selectedServerID == id { selectedServerID = servers.first?.id }
        if editingServerID == id { editingServerID = nil }
        if preferences.menuBarServerID == id { update { $0.menuBarServerID = nil } }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        servers.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Adds the built-in demo server, for trying MetriBar without Glances.
    func addDemoServer() {
        let demo = DemoServer.config()
        guard server(demo.id) == nil else { return }
        try? save(demo, password: .keep)
        selectedServerID = demo.id
    }

    private func persist() {
        configStore.save(servers)
        center.apply(servers)
    }

    // MARK: - Clients

    static func makeClient(
        for config: ServerConfig,
        credentials store: any CredentialStore,
        password: String? = nil,
        configuration: URLSessionConfiguration = .metriBar
    ) -> GlancesClient {
        if config.url == DemoServer.url {
            return DemoServer.client()
        }
        let credentials = config.username.map { username in
            Credentials(username: username, password: password ?? ((try? store.password(for: config.id)) ?? nil) ?? "")
        }
        let transport: URLSessionTransport
        if config.pinnedCertificate != nil || configuration != .metriBar {
            transport = URLSessionTransport(configuration: configuration, pinnedCertificate: config.pinnedCertificate)
        } else {
            transport = .shared
        }
        return GlancesClient(baseURL: config.url, credentials: credentials, transport: transport)
    }

    /// A client for the connection test: fails fast and uses the password
    /// from the editor if one was typed.
    func makeTestClient(for config: ServerConfig, password: String?) -> GlancesClient {
        Self.makeClient(
            for: config, credentials: credentials, password: password, configuration: .metriBarConnectionTest)
    }
}
