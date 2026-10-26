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
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
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
        .frame(minWidth: 820, minHeight: 560)
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

/// Header with server name and section tabs, followed by the selected section.
private struct ServerDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let monitor: ServerMonitor

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider()
            if let problem {
                ProblemBanner(problem: problem, monitor: monitor, onShowSettings: showSettings)
                    .padding([.horizontal, .top])
            }
            section(model.dashboardSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(monitor.isStale ? 0.5 : 1)
        }
        .navigationTitle(monitor.displayName)
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

    private var header: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HealthBadge(health: monitor.health)
                Text(monitor.displayName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button("Refresh", systemImage: "arrow.clockwise") { monitor.refresh() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut("r")
                    .help("Refresh now")
            }
            SectionTabs(selection: $model.dashboardSection)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 10)
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
        let system = monitor.snapshot.system.flatMap { $0.linuxDistro ?? $0.osName }
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

/// Section switcher inside the window content, so it never disappears into
/// the toolbar overflow. Shows icons only when the labels do not fit.
struct SectionTabs: View {
    @Binding var selection: DashboardSection

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabs(showTitles: true)
            tabs(showTitles: false)
        }
    }

    private func tabs(showTitles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(DashboardSection.allCases) { section in
                let isSelected = section == selection
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.systemImage)
                        if showTitles {
                            Text(section.title)
                        }
                    }
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .padding(.horizontal, showTitles ? 10 : 9)
                    .padding(.vertical, 5)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("\(section.title) (⌘\(String(section.shortcut)))")
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.6), in: Capsule())
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
