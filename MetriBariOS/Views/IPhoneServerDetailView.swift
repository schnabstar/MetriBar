import MetriBarKit
import SwiftUI

struct IPhoneServerDetailView: View {
    let monitor: ServerMonitor
    @Environment(AppModel.self) private var model
    @State private var refreshHapticTrigger = 0
    @State private var showsEditServer = false

    var body: some View {
        VStack(spacing: 0) {
            // Liquid Glass Floating Section Selector
            SectionPillBar(selection: Bindable(model).dashboardSection)
                .padding(.vertical, 8)
                .background(.bar)

            if let problem {
                ProblemBanner(problem: problem, monitor: monitor, onShowSettings: {
                    showsEditServer = true
                })
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            sectionContent
        }
        .navigationTitle(monitor.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    HStack(spacing: 6) {
                        HealthBadge(health: monitor.config.isEnabled ? monitor.health : .unknown)
                        Text(monitor.displayName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Refresh Now", systemImage: "arrow.clockwise") {
                        monitor.refresh()
                    }
                    Button("Edit Server…", systemImage: "pencil") {
                        showsEditServer = true
                    }
                    if let url = monitor.config.url.webURL {
                        Link(destination: url) {
                            Label("Open Web Interface", systemImage: "safari")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showsEditServer) {
            AddServerSheet(editingServerID: monitor.id)
        }
        .task(id: model.dashboardSection) {
            await monitor.keepActive(model.dashboardSection.feeds)
        }
        .sensoryHaptic(.impact(weight: .light), trigger: refreshHapticTrigger)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.dashboardSection {
        case .processes:
            CompactProcessesView(monitor: monitor)
                .refreshable { await refreshData() }
        case .containers:
            CompactContainersView(monitor: monitor)
                .refreshable { await refreshData() }
        case .storage:
            ScrollView {
                CompactStorageView(monitor: monitor)
            }
            .refreshable { await refreshData() }
        case .alerts:
            ScrollView {
                CompactAlertsView(monitor: monitor)
            }
            .refreshable { await refreshData() }
        case .network:
            ScrollView {
                CompactNetworkView(monitor: monitor)
            }
            .refreshable { await refreshData() }
        case .sensors:
            SensorsView(monitor: monitor)
                .refreshable { await refreshData() }
        default:
            ScrollView {
                sectionView(model.dashboardSection)
                    .padding(.vertical, 12)
            }
            .refreshable { await refreshData() }
        }
    }

    private func refreshData() async {
        refreshHapticTrigger += 1
        monitor.refresh()
        try? await Task.sleep(for: .milliseconds(600))
    }

    @ViewBuilder
    private func sectionView(_ section: DashboardSection) -> some View {
        switch section {
        case .overview:
            OverviewContent(monitor: monitor)
                .padding(.horizontal, 16)
        case .history:
            HistoryContent(monitor: monitor)
                .padding(.horizontal, 16)
        case .storage:
            CompactStorageView(monitor: monitor)
        case .network:
            CompactNetworkView(monitor: monitor)
        case .sensors:
            SensorsView(monitor: monitor)
        case .processes:
            CompactProcessesView(monitor: monitor)
        case .containers:
            CompactContainersView(monitor: monitor)
        case .alerts:
            CompactAlertsView(monitor: monitor)
        }
    }

    private var problem: ConnectionProblem? {
        switch monitor.state {
        case .needsCredentials, .unsupportedVersion: ConnectionProblem(monitor.state)
        case .failed where monitor.health == .offline: ConnectionProblem(monitor.state)
        default: nil
        }
    }

    private var subtitle: String? {
        let snapshot = monitor.snapshot
        let system = snapshot.system.flatMap { $0.linuxDistro ?? $0.osName }
        let uptime = snapshot.uptime.map { "up \(Format.duration($0.duration))" }
        return [system, uptime].compactMap { $0 }.joined(separator: " · ")
    }
}

