import MetriBarKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            if let monitor = model.selectedMonitor {
                ServerHeader(monitor: monitor, onSettings: { showSettings(editing: monitor.id) })
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

    private var footer: some View {
        HStack {
            Button("Open Dashboard", action: showDashboard)
                .keyboardShortcut("d")
                .disabled(model.servers.isEmpty)
            if let monitor = model.selectedMonitor, monitor.config.url != DemoServer.url {
                Button("Web UI") { openURL(monitor.config.url) }
                    .help("Open the Glances web interface in the browser")
            }
            Spacer()
            Button("Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .labelStyle(.iconOnly)
            .keyboardShortcut("q")
            .help("Quit MetriBar")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

/// Server name, picker for other servers, status line and actions.
struct ServerHeader: View {
    @Environment(AppModel.self) private var model
    let monitor: ServerMonitor
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                HealthBadge(health: monitor.health)
                serverPicker
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { monitor.refresh() }
                    .keyboardShortcut("r")
                    .help("Refresh now")
                Button("Server Settings…", systemImage: "gearshape", action: onSettings)
                    .keyboardShortcut(",")
                    .help("Server settings")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

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

    @ViewBuilder
    private var serverPicker: some View {
        if model.center.monitors.count > 1 {
            Menu {
                ForEach(model.center.monitors) { other in
                    Button {
                        model.selectedServerID = other.id
                    } label: {
                        Label(
                            other.displayName,
                            systemImage: other.id == monitor.id ? "checkmark" : other.health.symbolName)
                    }
                }
            } label: {
                Text(monitor.displayName).font(.headline)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Switch server")
        } else {
            Text(monitor.displayName).font(.headline)
        }
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
