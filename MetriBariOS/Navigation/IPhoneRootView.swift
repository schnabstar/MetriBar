import MetriBarKit
import SwiftUI

struct IPhoneRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedTab: IPhoneTab = .servers
    @State private var serverPath: [UUID] = []

    enum IPhoneTab: Hashable {
        case servers, alerts, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Servers", systemImage: "server.rack", value: .servers) {
                NavigationStack(path: $serverPath) {
                    IPhoneServerListView()
                        .navigationDestination(for: UUID.self) { serverID in
                            if let monitor = model.center.monitor(for: serverID) {
                                IPhoneServerDetailView(monitor: monitor)
                            } else {
                                ContentUnavailableView("Server Not Found", systemImage: "server.rack")
                            }
                        }
                }
            }
            Tab("Alerts", systemImage: "exclamationmark.triangle", value: .alerts) {
                NavigationStack {
                    IPhoneAlertsListView()
                }
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                NavigationStack {
                    IOSSettingsView()
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onChange(of: model.dashboardRequest) { _, _ in
            if model.dashboardSection == .alerts {
                selectedTab = .servers
                if let monitor = model.selectedMonitor {
                    serverPath = [monitor.id]
                }
            } else {
                selectedTab = .servers
                serverPath = model.selectedMonitor.map { [$0.id] } ?? []
            }
        }
    }
}
