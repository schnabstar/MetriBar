import MetriBarKit
import SwiftUI

/// The menu bar window. It gets its Liquid Glass background from the system;
/// the controls inside use standard styles instead of more glass.
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            if let monitor = model.selectedMonitor {
                ServerHeader(monitor: monitor)
                Divider()
                ServerSummary(monitor: monitor, onShowSettings: { showSettings(editing: monitor.id) })
                    .task(id: monitor.id) { await monitor.keepActive([.core, .containers]) }
            } else {
                OnboardingView(
                    onAddServer: { showSettings(addingServer: true) },
                    onTryDemo: { model.addDemoServer() }
                )
            }
            Divider()
            footer
        }
        .frame(width: 360)
    }

    /// Menu-like rows, as at the bottom of Control Center modules.
    private var footer: some View {
        VStack(spacing: 0) {
            Button("Open Dashboard", action: showDashboard)
                .keyboardShortcut("d")
                .disabled(model.servers.isEmpty)
            if let monitor = model.selectedMonitor, monitor.config.url != DemoServer.url {
                Button("Open Glances Web UI") { openURL(monitor.config.url) }
            }
            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            Button("Settings…") { showSettings(editing: model.selectedMonitor?.id) }
                .keyboardShortcut(",")
            Button("About MetriBar", action: AboutPanel.show)
            Button("Quit MetriBar") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.menuRow)
        .padding(6)
    }

    private func showDashboard() {
        openWindow(id: SceneID.dashboard)
        NSApplication.shared.activate()
    }

    private func showSettings(editing serverID: UUID? = nil, addingServer: Bool = false) {
        model.settingsTab = .servers
        if let serverID { model.editingServerID = serverID }
        model.isAddingServer = addingServer
        NSApplication.shared.activate()
        openSettings()
    }
}

/// Server name, picker for other servers, status line and refresh.
struct ServerHeader: View {
    @Environment(AppModel.self) private var model
    let monitor: ServerMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                HealthBadge(health: monitor.health)
                serverPicker
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { monitor.refresh() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut("r")
                    .help("Refresh now")
            }

            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text(statusLine(now: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// A pull-down with a native check mark; the health symbols stay visible.
    @ViewBuilder
    private var serverPicker: some View {
        if model.center.monitors.count > 1 {
            Menu {
                Picker("Server", selection: selection) {
                    ForEach(model.center.monitors) { other in
                        Label(other.displayName, systemImage: other.health.symbolName)
                            .tag(other.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(monitor.displayName).font(.headline)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.visible)
            .fixedSize()
            .help("Switch server")
        } else {
            Text(monitor.displayName).font(.headline)
        }
    }

    private var selection: Binding<UUID> {
        Binding(get: { monitor.id }, set: { model.selectedServerID = $0 })
    }

    private func statusLine(now: Date) -> String {
        let system = monitor.snapshot.system.flatMap { $0.linuxDistro ?? $0.osName }
        let glances = monitor.snapshot.status?.glancesVersion.map { "Glances \($0)" }
        let updated: String? =
            switch monitor.state {
            case .connecting where monitor.lastSuccess == nil: String(localized: "Connecting…")
            case .failed where !monitor.isStale: String(localized: "Retrying…")
            default: monitor.lastSuccess.map { Format.relative($0, now: now) }
            }
        return [system, glances, updated].compactMap { $0 }.joined(separator: " · ")
    }
}
