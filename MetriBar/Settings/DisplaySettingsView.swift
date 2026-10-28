import SwiftUI

struct DisplaySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker("Menu bar shows", selection: valueBinding) {
                    Text("Status icon only").tag(Preferences.MenuBarValue.none)
                    Text("Status icon and CPU usage").tag(Preferences.MenuBarValue.cpu)
                    Text("Status icon and memory usage").tag(Preferences.MenuBarValue.memory)
                    Text("Status icon, CPU and memory usage").tag(Preferences.MenuBarValue.cpuAndMemory)
                }
                .pickerStyle(.radioGroup)

                Picker("Value of", selection: serverBinding) {
                    Text("Server selected in the menu").tag(UUID?.none)
                    ForEach(model.servers) { config in
                        Text(config.displayName).tag(UUID?.some(config.id))
                    }
                }
                .disabled(model.preferences.menuBarValue == .none)
            } footer: {
                Text(
                    "The icon always shows the state of all servers: a warning or error on any server, such as high usage, a high temperature or an unhealthy container, changes its shape."
                )
            }
        }
        .formStyle(.grouped)
    }

    private var valueBinding: Binding<Preferences.MenuBarValue> {
        Binding(get: { model.preferences.menuBarValue }, set: { value in model.update { $0.menuBarValue = value } })
    }

    private var serverBinding: Binding<UUID?> {
        Binding(get: { model.preferences.menuBarServerID }, set: { id in model.update { $0.menuBarServerID = id } })
    }
}
