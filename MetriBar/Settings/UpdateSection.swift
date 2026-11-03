import MetriBarKit
import SwiftUI

/// The "Updates" section of the general settings: the opt-in switch, the
/// result of the last check and the links to the new release.
struct UpdateSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let updates = model.updates
        Section {
            Toggle("Check for updates automatically", isOn: automaticBinding)

            LabeledContent {
                Button("Check Now") { Task { await updates.checkNow() } }
                    .disabled(updates.isChecking)
            } label: {
                status(updates)
            }

            if let update = updates.available {
                HStack {
                    Button("Release Notes") { openURL(update.pageURL) }
                    Button("Download") { openURL(update.diskImageURL ?? update.pageURL) }
                    Spacer()
                    if updates.announced == nil {
                        Text("Hidden in the menu bar window").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Skip This Version") { updates.skipAvailableVersion() }
                    }
                }
            }
        } header: {
            Text("Updates")
        } footer: {
            Text(
                "Off by default. When on, MetriBar asks GitHub once a day whether a newer version exists. GitHub sees your IP address; nothing else is sent. Updates are never installed automatically."
            )
        }
    }

    @ViewBuilder
    private func status(_ updates: UpdateModel) -> some View {
        switch updates.state {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…")
            }
        case .available(let update):
            Label {
                Text("MetriBar \(update.version) is available.")
            } icon: {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
            }
        case .upToDate:
            Text("MetriBar is up to date.")
        case .failed(let error):
            Text(error.message)
        case .idle:
            if let lastCheck = updates.lastCheck {
                Text("Last checked \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("MetriBar \(AppModel.currentVersion.description)")
            }
        }
    }

    private var automaticBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.checksForUpdates },
            set: { value in model.update { $0.checksForUpdates = value } })
    }
}

extension UpdateError {
    var message: String {
        switch self {
        case .network: String(localized: "Could not reach GitHub.")
        case .rateLimited: String(localized: "GitHub is limiting requests right now. Try again later.")
        case .notFound, .invalidResponse: String(localized: "GitHub sent an unexpected answer.")
        }
    }
}
