import MetriBarKit
import SwiftUI

/// Notifications about problems on the servers: off until turned on.
struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    var body: some View {
        let settings = model.preferences.notifications
        Form {
            Section {
                Toggle("Notify about problems", isOn: enabledBinding)
                if settings.isEnabled, model.notifier.authorization == .denied {
                    LabeledContent {
                        Button("Open System Settings…") { openURL(Self.settingsURL) }
                    } label: {
                        Label(
                            "Notifications are turned off for MetriBar in System Settings.", systemImage: "bell.slash")
                    }
                }
                Button("Send Test Notification", action: sendTest)
                    .disabled(model.notifier.authorization == .denied)
            } footer: {
                Text(
                    "MetriBar creates notifications on this Mac from what your servers report. Nothing is sent anywhere. You can turn off single servers in their settings."
                )
            }

            Section {
                Picker("Notify from", selection: binding(\.threshold)) {
                    Text("Warning").tag(NotificationSettings.Threshold.warning)
                    Text("Critical").tag(NotificationSettings.Threshold.critical)
                }
                Picker("Problem has to last", selection: binding(\.holdSeconds)) {
                    ForEach(NotificationSettings.holdChoices, id: \.self) { seconds in
                        Text(holdLabel(seconds)).tag(seconds)
                    }
                }
                Toggle("Server cannot be reached", isOn: binding(\.notifiesOffline))
                Toggle("Value is back to normal", isOn: binding(\.notifiesRecovery))
            } header: {
                Text("What to report")
            } footer: {
                Text(
                    "A short spike is not reported. The same problem is reported at most every 15 minutes, unless it gets worse."
                )
            }
            .disabled(!settings.isEnabled)

            Section {
                Toggle("Quiet hours", isOn: quietBinding(\.isEnabled))
                if settings.quietHours.isEnabled {
                    DatePicker("From", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text(
                    "Nothing is reported during quiet hours. A problem that is still there afterwards is reported then."
                )
            }
            .disabled(!settings.isEnabled)
        }
        .formStyle(.grouped)
        .task { await model.notifier.refresh() }
    }

    /// Asks for permission first if the system has not been asked yet.
    private func sendTest() {
        Task {
            if model.notifier.authorization != .allowed { await model.notifier.requestAuthorization() }
            model.notifier.postTest()
        }
    }

    // MARK: Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.notifications.isEnabled },
            set: { model.setNotificationsEnabled($0) })
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<NotificationSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.preferences.notifications[keyPath: keyPath] },
            set: { value in model.update { $0.notifications[keyPath: keyPath] = value } })
    }

    private func quietBinding(_ keyPath: WritableKeyPath<QuietHours, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.preferences.notifications.quietHours[keyPath: keyPath] },
            set: { value in model.update { $0.notifications.quietHours[keyPath: keyPath] = value } })
    }

    /// A time of day, stored as minutes since midnight.
    private func minuteBinding(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = model.preferences.notifications.quietHours[keyPath: keyPath]
                return Calendar.current.date(
                    byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: .now))
                    ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                model.update { $0.notifications.quietHours[keyPath: keyPath] = minutes }
            })
    }

    private func holdLabel(_ seconds: Int) -> String {
        seconds == 0
            ? String(localized: "Immediately")
            : Duration.seconds(seconds).formatted(.units(allowed: [.minutes], width: .wide))
    }
}
