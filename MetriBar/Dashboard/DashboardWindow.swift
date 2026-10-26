import MetriBarKit
import SwiftUI

/// Server and section shown in the dashboard: the sidebar selection.
struct DashboardDestination: Hashable {
    let serverID: UUID
    let section: DashboardSection
}

/// Sidebar with one collapsible group of sections per server, like the
/// accounts and mailboxes in Mail. Eight sections do not fit into the
/// toolbar: even the tabs picker of macOS 27 moves into the overflow menu
/// next to the title.
struct DashboardWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    /// Servers whose sections the user collapsed.
    @State private var collapsed: Set<UUID> = []
    /// The sidebar holds the navigation, so it starts visible, also for
    /// users who hid the server-only sidebar of earlier versions.
    @SceneStorage("showsSidebar") private var showsSidebar = true

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            List(selection: selection) {
                ForEach(model.center.monitors) { monitor in
                    Section(isExpanded: isExpanded(monitor.id)) {
                        ForEach(DashboardSection.allCases) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(DashboardDestination(serverID: monitor.id, section: section))
                        }
                    } header: {
                        SidebarServerHeader(monitor: monitor)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
            .safeAreaBar(edge: .bottom) {
                Button("Add Server…", systemImage: "plus", action: addServer)
                    .buttonStyle(.borderless)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            if let monitor = model.selectedMonitor {
                ServerDetail(monitor: monitor)
                    .id(monitor.id)
            } else {
                ContentUnavailableView {
                    Label("No Servers", systemImage: "server.rack")
                } description: {
                    Text("Add a Glances 5 server to see its details here.")
                } actions: {
                    Button("Add Server…", action: addServer)
                    Button("Try with Demo Data") { model.addDemoServer() }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear(perform: DockPresence.show)
        .onDisappear(perform: DockPresence.hide)
    }

    private var selection: Binding<DashboardDestination?> {
        Binding {
            model.selectedMonitor.map { DashboardDestination(serverID: $0.id, section: model.dashboardSection) }
        } set: { destination in
            guard let destination else { return }
            model.selectedServerID = destination.serverID
            model.dashboardSection = destination.section
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            showsSidebar ? .all : .detailOnly
        } set: { visibility in
            showsSidebar = visibility != .detailOnly
        }
    }

    private func isExpanded(_ id: UUID) -> Binding<Bool> {
        Binding {
            !collapsed.contains(id)
        } set: { expanded in
            if expanded { collapsed.remove(id) } else { collapsed.insert(id) }
        }
    }

    private func addServer() {
        model.settingsTab = .servers
        model.isAddingServer = true
        NSApplication.shared.activate()
        openSettings()
    }
}

private struct SidebarServerHeader: View {
    let monitor: ServerMonitor

    var body: some View {
        Label {
            Text(monitor.displayName)
                .lineLimit(1)
        } icon: {
            HealthBadge(health: monitor.config.isEnabled ? monitor.health : .unknown)
        }
        .help(monitor.config.isEnabled ? monitor.health.label : String(localized: "Not monitored"))
    }
}

/// The selected section with server name and status in the toolbar.
private struct ServerDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let monitor: ServerMonitor

    var body: some View {
        section(model.dashboardSection)
            // Centers empty states; scroll views and tables fill the space anyway.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(monitor.isStale ? 0.5 : 1)
            .safeAreaBar(edge: .top) {
                if let problem {
                    ProblemBanner(problem: problem, monitor: monitor, onShowSettings: showSettings)
                        .padding([.horizontal, .top])
                }
            }
            .navigationTitle(monitor.displayName)
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") { monitor.refresh() }
                        .help("Refresh now")
                }
            }
            .focusedSceneValue(\.dashboardMonitor, monitor)
            .task(id: model.dashboardSection) {
                await monitor.keepActive(model.dashboardSection.feeds)
            }
    }

    @ViewBuilder
    private func section(_ section: DashboardSection) -> some View {
        switch section {
        case .overview: OverviewView(monitor: monitor)
        case .history: HistoryView(monitor: monitor)
        case .storage: StorageView(monitor: monitor)
        case .network: NetworkView(monitor: monitor)
        case .sensors: SensorsView(monitor: monitor)
        case .processes: ProcessesView(monitor: monitor)
        case .containers: ContainersView(monitor: monitor)
        case .alerts: AlertsView(monitor: monitor)
        }
    }

    private var problem: ConnectionProblem? {
        switch monitor.state {
        case .needsCredentials, .unsupportedVersion: ConnectionProblem(monitor.state)
        case .failed where monitor.health == .offline: ConnectionProblem(monitor.state)
        default: nil
        }
    }

    /// What the section shows, falling back to the system and uptime.
    private var subtitle: String {
        let snapshot = monitor.snapshot
        let summary: String? =
            switch model.dashboardSection {
            case .history: HistoryContent.summary(snapshot.history)
            case .processes: ProcessesView.summary(snapshot)
            case .containers: ContainersView.summary(snapshot)
            default: nil
            }
        if let summary { return summary }
        let system = snapshot.system.flatMap { $0.linuxDistro ?? $0.osName }
        let glances = snapshot.status?.glancesVersion.map { "Glances \($0)" }
        let uptime = snapshot.uptime.map { String(localized: "up \(Format.duration($0.duration))") }
        return [system, glances, uptime].compactMap { $0 }.joined(separator: " · ")
    }

    private func showSettings() {
        model.settingsTab = .servers
        model.editingServerID = monitor.id
        NSApplication.shared.activate()
        openSettings()
    }
}

extension FocusedValues {
    /// Server shown in the focused dashboard window, for the menu commands.
    @Entry var dashboardMonitor: ServerMonitor?
}

/// MetriBar is a menu bar app without a Dock icon. While the dashboard is
/// open it becomes a regular app so the window shows up in the Dock and in
/// the app switcher.
enum DockPresence {
    static func show() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    static func hide() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
