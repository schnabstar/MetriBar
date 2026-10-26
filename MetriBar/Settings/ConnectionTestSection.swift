import MetriBarKit
import SwiftUI

/// Runs `ConnectionTest` with the values of the editor, before saving.
struct ConnectionTestSection: View {
    let draft: ServerDraft
    let hasStoredPassword: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var report: ConnectionTestReport?
    @State private var isTesting = false

    var body: some View {
        Section("Connection Test") {
            HStack {
                Button("Test Connection", action: test)
                    .disabled(isTesting || (try? draft.makeConfig()) == nil)
                if isTesting { ProgressView().controlSize(.small) }
            }
            if let report {
                stepRow(String(localized: "Server reachable and running Glances 5"), report.server)
                stepRow(String(localized: "Login"), report.authentication)
                stepRow(String(localized: "Values readable"), report.data)
                if report.succeeded {
                    summary(report)
                } else if let problem = report.problem {
                    problemDetails(problem)
                }
            }
        }
        .onChange(of: draft) { report = nil }
    }

    private func stepRow(_ title: String, _ step: ConnectionTestReport.Step) -> some View {
        HStack(spacing: 8) {
            switch step {
            case .pending:
                Image(systemName: "circle.dotted").foregroundStyle(.secondary)
            case .passed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .skipped:
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            Text(title)
                .foregroundStyle(step == .skipped ? .secondary : .primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func summary(_ report: ConnectionTestReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let version = report.glancesVersion, let host = report.hostname {
                Text("Glances \(version) on \(host)")
            }
            Text(
                report.plugins.contains("containers")
                    ? String(localized: "Containers: available") : String(localized: "Containers: plugin not active"))
            Text(
                report.plugins.contains("sensors")
                    ? String(localized: "Sensors: available") : String(localized: "Sensors: not available"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func problemDetails(_ problem: ConnectionProblem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(problem.title).font(.headline)
            Text(problem.advice(hasCredentials: draft.requiresPassword))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if problem == .localNetworkDenied {
                Button("Open Privacy Settings") { openURL(LocalNetworkCheck.settingsURL) }
            }
        }
    }

    private func test() {
        guard let config = try? draft.makeConfig() else { return }
        isTesting = true
        var pending = ConnectionTestReport()
        pending.server = .pending
        report = pending
        let password: String? = draft.passwordEdited ? draft.password : nil
        let client = model.makeTestClient(for: config, password: password)
        Task {
            report = await ConnectionTest.run(client: client)
            isTesting = false
        }
    }
}
