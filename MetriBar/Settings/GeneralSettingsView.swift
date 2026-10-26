import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var loginItemStatus = LoginItem.status
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Picker("In the background", selection: baseBinding) {
                    ForEach(Preferences.baseIntervalChoices, id: \.self) { seconds in
                        Text("Every \(seconds) seconds").tag(seconds)
                    }
                }
                Picker("While the menu or dashboard is open", selection: liveBinding) {
                    ForEach(Preferences.liveIntervalChoices, id: \.self) { seconds in
                        Text(
                            seconds == 1
                                ? String(localized: "Every second") : String(localized: "Every \(seconds) seconds")
                        )
                        .tag(seconds)
                    }
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("MetriBar only asks the servers you add. It collects no data and sends nothing anywhere else.")
            }

            Section {
                Toggle("Open MetriBar at login", isOn: loginBinding)
                if loginItemStatus == .requiresApproval {
                    LabeledContent {
                        Button("Open System Settings…") { SMAppService.openSystemSettingsLoginItems() }
                    } label: {
                        Text("Allow MetriBar in System Settings › General › Login Items.")
                    }
                }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItemStatus = LoginItem.status }
    }

    private var baseBinding: Binding<Int> {
        Binding(
            get: { model.preferences.baseIntervalSeconds },
            set: { value in model.update { $0.baseIntervalSeconds = value } })
    }

    private var liveBinding: Binding<Int> {
        Binding(
            get: { model.preferences.liveIntervalSeconds },
            set: { value in model.update { $0.liveIntervalSeconds = value } })
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
            set: { enabled in
                do {
                    try LoginItem.setEnabled(enabled)
                    loginItemError = nil
                } catch {
                    loginItemError = error.localizedDescription
                }
                loginItemStatus = LoginItem.status
            }
        )
    }
}
