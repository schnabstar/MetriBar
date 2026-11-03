import Foundation
import MetriBarKit
import Observation

enum SettingsTab: String, Hashable {
    case servers, display, notifications, thresholds, general
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
    let updates: UpdateModel
    let alerts: AlertCenter
    let notifier = NotificationService()
    private(set) var servers: [ServerConfig] = []
    private(set) var rules: [ThresholdRule] = []
    /// Recent values of the menu bar items, for the trend line.
    private(set) var menuBarSampler = MenuBarSampler()
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

    /// Increases when something outside a view, such as a click on a
    /// notification, wants the dashboard window to open.
    private(set) var dashboardRequest = 0

    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let ruleStore: RuleStore
    @ObservationIgnored private let credentials: any CredentialStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let events = SystemEventObserver()
    @ObservationIgnored private var samplerTask: Task<Void, Never>?
    /// `false` for throwaway models of the debug tools, which must not
    /// touch the system notification center.
    @ObservationIgnored private let deliversNotifications: Bool

    private enum Keys {
        static let preferences = "preferences"
        static let selectedServer = "selectedServer"
    }

    init(
        configStore: ConfigStore = ConfigStore(),
        ruleStore: RuleStore = RuleStore(),
        credentials: any CredentialStore = AppKeychain.store,
        defaults: UserDefaults = .standard,
        observeSystemEvents: Bool = true,
        deliversNotifications: Bool = true,
        updateTransport: any HTTPTransport = URLSessionTransport(configuration: .metriBarConnectionTest)
    ) {
        self.configStore = configStore
        self.ruleStore = ruleStore
        self.credentials = credentials
        self.defaults = defaults
        self.deliversNotifications = deliversNotifications
        let preferences =
            defaults.data(forKey: Keys.preferences)
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        self.preferences = preferences
        selectedServerID = defaults.string(forKey: Keys.selectedServer).flatMap(UUID.init(uuidString:))
        center = MonitorCenter(settings: preferences.pollingSettings) { [credentials] config in
            Self.makeClient(for: config, credentials: credentials)
        }
        updates = UpdateModel(currentVersion: Self.currentVersion, transport: updateTransport, defaults: defaults)
        let notifier = notifier
        alerts = AlertCenter(
            settings: deliversNotifications ? preferences.notifications : NotificationSettings(),
            monitors: { [center] in center.monitors },
            deliver: { notices in notifier.post(notices) })
        servers = configStore.load()
        rules = ruleStore.load()
        center.setRules(rules)
        center.apply(servers)
        if preferences.checksForUpdates { updates.startAutomaticChecks() }
        if observeSystemEvents {
            events.start { [weak self] event in
                self?.center.handle(event)
                self?.alerts.handle(event)
            }
        }
        if deliversNotifications {
            notifier.onOpenServer = { [weak self] id in self?.showAlerts(for: id) }
            notifier.activate()
        }
        applyNotificationSettings()
        updateTrendSampling()
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
        let previous = preferences
        let pollingChanged = next.pollingSettings != previous.pollingSettings
        preferences = next
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Keys.preferences)
        }
        if pollingChanged {
            center.update(settings: next.pollingSettings)
        }
        if next.notifications != previous.notifications {
            applyNotificationSettings()
        } else if next.menuBarItems != previous.menuBarItems {
            refreshBackgroundFeeds()
        }
        if next.menuBarItems != previous.menuBarItems || next.menuBarTrend != previous.menuBarTrend {
            updateTrendSampling()
        }
        if next.checksForUpdates != previous.checksForUpdates {
            if next.checksForUpdates {
                updates.startAutomaticChecks()
            } else {
                updates.stopAutomaticChecks()
            }
        }
    }

    /// Samples the menu bar values every ten seconds while the trend line
    /// is on; the loop does not run, and nothing is kept, otherwise.
    private func updateTrendSampling() {
        let wanted = preferences.menuBarTrend && !preferences.menuBarItems.isEmpty
        guard wanted else {
            samplerTask?.cancel()
            samplerTask = nil
            if menuBarSampler != MenuBarSampler() { menuBarSampler = MenuBarSampler() }
            return
        }
        guard samplerTask == nil else { return }
        samplerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sampleMenuBar()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func sampleMenuBar() {
        let monitor = menuBarMonitor
        let readable = monitor.map { $0.health != .offline && $0.health != .unknown } ?? false
        menuBarSampler.record(
            serverID: monitor?.id, items: preferences.menuBarItems, snapshot: readable ? monitor?.snapshot : nil)
    }

    /// Starts or stops the alerts.
    private func applyNotificationSettings() {
        if deliversNotifications { alerts.update(settings: preferences.notifications) }
        refreshBackgroundFeeds()
    }

    /// Fetches what is needed in the background beyond the usual: the file
    /// systems while notifications watch them, and the feeds of the rules
    /// and of the values in the menu bar.
    private func refreshBackgroundFeeds() {
        var feeds = ThresholdRule.requiredFeeds(rules).union(MenuBarMetric.requiredFeeds(preferences.menuBarItems))
        if preferences.notifications.isEnabled { feeds.insert(.storage) }
        center.setExtraBackgroundFeeds(feeds)
    }

    /// Turns notifications on or off. Turning them on asks the system for
    /// permission the first time.
    func setNotificationsEnabled(_ enabled: Bool) {
        update { $0.notifications.isEnabled = enabled }
        guard enabled else { return }
        Task { await notifier.requestAuthorization() }
    }

    /// Shows the alerts of a server in the dashboard, for example after a
    /// click on a notification.
    func showAlerts(for serverID: UUID?) {
        if let serverID, server(serverID) != nil { selectedServerID = serverID }
        dashboardSection = .alerts
        dashboardRequest += 1
    }

    /// The version of the running app, from the Info.plist.
    static var currentVersion: AppVersion {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
            ?? AppVersion(major: 0, minor: 0, patch: 0)
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
        if rules.contains(where: { $0.serverID == id }) {
            rules.removeAll { $0.serverID == id }
            persistRules()
        }
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

    // MARK: - Rules

    /// Adds a rule or replaces the one with the same `id`.
    func saveRule(_ rule: ThresholdRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persistRules()
    }

    func removeRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
        persistRules()
    }

    /// A copy right below the original.
    @discardableResult
    func duplicateRule(_ id: UUID) -> UUID? {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = rules[index]
        copy.id = UUID()
        rules.insert(copy, at: index + 1)
        persistRules()
        return copy.id
    }

    private func persistRules() {
        ruleStore.save(rules)
        center.setRules(rules)
        refreshBackgroundFeeds()
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
