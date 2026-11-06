import MetriBarKit
import SwiftUI
import UIKit

struct IPadRootView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsAddServer = false
    @State private var showsSettings = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            serverSidebar
                .navigationTitle("Servers")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
                .safeAreaBar(edge: .bottom) {
                    HStack {
                        Button {
                            showsAddServer = true
                        } label: {
                            Label("Add Server", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        .hoverEffect()
                        .keyboardShortcut("n", modifiers: .command)

                        Spacer()

                        Button {
                            showsSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                        .buttonStyle(.borderless)
                        .hoverEffect()
                        .keyboardShortcut(",", modifiers: .command)
                    }
                    .padding(12)
                }
        } content: {
            if let monitor = model.selectedMonitor {
                sectionList(monitor: monitor)
                    .navigationTitle(monitor.displayName)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            } else {
                ContentUnavailableView("Select a Server", systemImage: "server.rack")
            }
        } detail: {
            if let monitor = model.selectedMonitor {
                detailView(monitor: monitor)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Refresh", systemImage: "arrow.clockwise") {
                                monitor.refresh()
                            }
                            .keyboardShortcut("r", modifiers: .command)
                            .hoverEffect()
                        }
                    }
            } else {
                ContentUnavailableView {
                    Label("No Server Selected", systemImage: "server.rack")
                } description: {
                    Text("Select a server from the sidebar or add a new one.")
                } actions: {
                    Button("Add Server…") { showsAddServer = true }
                    Button("Try with Demo Data") { model.addDemoServer() }
                }
            }
        }
        .sheet(isPresented: $showsAddServer) {
            AddServerSheet()
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                IOSSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsSettings = false }
                        }
                    }
            }
        }
    }

    private var serverSidebar: some View {
        List(selection: Bindable(model).selectedServerID) {
            ForEach(model.center.monitors) { monitor in
                HStack(spacing: 8) {
                    HealthBadge(health: monitor.config.isEnabled ? monitor.health : .unknown)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(monitor.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(monitor.config.url.host ?? monitor.config.url.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(monitor.id)
                .hoverEffect()
            }
        }
    }

    private func sectionList(monitor: ServerMonitor) -> some View {
        let selection = Binding<DashboardSection?>(
            get: { model.dashboardSection },
            set: { newValue in if let newValue { model.dashboardSection = newValue } }
        )
        return List(DashboardSection.allCases, selection: selection) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
                .keyboardShortcut(KeyEquivalent(section.shortcut), modifiers: .command)
                .hoverEffect()
        }
    }

    @ViewBuilder
    private func detailView(monitor: ServerMonitor) -> some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if let problem = connectionProblem(for: monitor) {
                        ProblemBanner(problem: problem, monitor: monitor, onShowSettings: {
                            showsSettings = true
                        })
                        .padding(.horizontal)
                    }

                    switch model.dashboardSection {
                    case .overview:
                        OverviewContent(monitor: monitor)
                            .padding()
                    case .history:
                        HistoryContent(monitor: monitor)
                            .padding()
                    case .storage:
                        StorageView(monitor: monitor)
                            .padding()
                    case .network:
                        NetworkView(monitor: monitor)
                            .padding()
                    case .sensors:
                        SensorsView(monitor: monitor)
                    case .processes:
                        ProcessesView(monitor: monitor)
                    case .containers:
                        IPadContainersView(monitor: monitor)
                    case .alerts:
                        AlertsView(monitor: monitor)
                    }
                }
                .padding(.vertical)
            }
            .refreshable {
                monitor.refresh()
            }
        }
        .navigationTitle("\(monitor.displayName) – \(model.dashboardSection.title)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.dashboardSection) {
            await monitor.keepActive(model.dashboardSection.feeds)
        }
    }

    private func connectionProblem(for monitor: ServerMonitor) -> ConnectionProblem? {
        switch monitor.state {
        case .needsCredentials, .unsupportedVersion: ConnectionProblem(monitor.state)
        case .failed where monitor.health == .offline: ConnectionProblem(monitor.state)
        default: nil
        }
    }
}
