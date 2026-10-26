import MetriBarKit
import SwiftUI

struct DashboardWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedServerID) {
                ForEach(model.center.monitors) { monitor in
                    SidebarRow(monitor: monitor).tag(monitor.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
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
        .onAppear(perform: DockPresence.show)
        .onDisappear(perform: DockPresence.hide)
    }

    private func addServer() {
        model.settingsTab = .servers
        model.isAddingServer = true
        NSApplication.shared.activate()
        openSettings()
    }
}

private struct SidebarRow: View {
    let monitor: ServerMonitor

    var body: some View {
        HStack(spacing: 8) {
            HealthBadge(health: monitor.config.isEnabled ? monitor.health : .unknown)
            VStack(alignment: .leading, spacing: 1) {
                Text(monitor.displayName).lineLimit(1)
                if let cpu = monitor.snapshot.cpu?.value.total, let memory = monitor.snapshot.memory?.value.percent {
                    Text("CPU \(Format.percent(cpu)) · RAM \(Format.percent(memory))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(monitor.config.isEnabled ? 1 : 0.5)
    }
}

/// Header, section picker and the selected section of one server.
private struct ServerDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let monitor: ServerMonitor

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let problem {
                ProblemBanner(problem: problem, monitor: monitor, onShowSettings: showSettings)
                    .padding([.horizontal, .top])
            }
            section(model.dashboardSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(monitor.isStale ? 0.5 : 1)
        }
        .navigationTitle(monitor.displayName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $model.dashboardSection) {
                    ForEach(DashboardSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { monitor.refresh() }
                    .keyboardShortcut("r")
                    .help("Refresh now")
            }
        }
        .background {
            // ⌘1 … ⌘7 switch sections.
            ForEach(DashboardSection.allCases) { section in
                Button(section.title) { model.dashboardSection = section }
                    .keyboardShortcut(KeyEquivalent(section.shortcut), modifiers: .command)
                    .hidden()
            }
        }
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
        case .network: NetworkSensorsView(monitor: monitor)
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

    private var subtitle: String {
        let system = monitor.snapshot.system?.hrName
        let glances = monitor.snapshot.status?.glancesVersion.map { "Glances \($0)" }
        let uptime = monitor.snapshot.uptime.map { String(localized: "up \(Format.duration($0.duration))") }
        return [system, glances, uptime].compactMap { $0 }.joined(separator: " · ")
    }

    private func showSettings() {
        model.settingsTab = .servers
        model.editingServerID = monitor.id
        NSApplication.shared.activate()
        openSettings()
    }
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
