import MetriBarKit
import SwiftUI

struct DisplaySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.preferences.menuBarItems
        Form {
            Section {
                ForEach(0..<MenuBarMetric.maximumCount, id: \.self) { slot in
                    Picker("Value \(slot + 1)", selection: slotBinding(slot)) {
                        Text("None").tag(MenuBarMetric?.none)
                        Divider()
                        ForEach(MenuBarMetric.allCases, id: \.self) { metric in
                            Text(metric.title).tag(MenuBarMetric?.some(metric))
                        }
                    }
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Text(
                    "The status icon is always there. The values appear next to it, in this order. If the menu bar is full, macOS hides items that do not fit; fewer values and the symbols style take less room."
                )
            }

            Section {
                Picker("Style", selection: binding(\.menuBarStyle)) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                Toggle("Trend line after the first value", isOn: binding(\.menuBarTrend))
                Picker("Show values", selection: binding(\.menuBarVisibility)) {
                    ForEach(MenuBarVisibility.allCases, id: \.self) { visibility in
                        Text(visibility.title).tag(visibility)
                    }
                }
                Picker("Values of", selection: serverBinding) {
                    Text("Server selected in the menu").tag(UUID?.none)
                    ForEach(model.servers) { config in
                        Text(config.displayName).tag(UUID?.some(config.id))
                    }
                }
            } footer: {
                Text(
                    "The icon always shows the state of all servers: a warning or error on any server, such as high usage, a high temperature, an unhealthy container or one of your own rules, changes its shape."
                )
            }
            .disabled(items.isEmpty)
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } })
    }

    private var serverBinding: Binding<UUID?> {
        binding(\.menuBarServerID)
    }

    /// One of the places next to the icon. Choosing "None" closes the gap,
    /// and a value that is already shown moves to the new place.
    private func slotBinding(_ slot: Int) -> Binding<MenuBarMetric?> {
        Binding(
            get: {
                let items = model.preferences.menuBarItems
                return items.indices.contains(slot) ? items[slot] : nil
            },
            set: { metric in
                model.update { preferences in
                    var items = preferences.menuBarItems
                    if let metric { items.removeAll { $0 == metric } }
                    if let metric, items.indices.contains(slot) {
                        items.insert(metric, at: slot)
                    } else if let metric {
                        items.append(metric)
                    } else if items.indices.contains(slot) {
                        items.remove(at: slot)
                    }
                    preferences.menuBarItems = Preferences.normalized(items)
                }
            })
    }
}
