import AppKit
import MetriBarKit
import SwiftUI

/// Explains why a server cannot be read and offers the matching fix.
struct ProblemBanner: View {
    let problem: ConnectionProblem
    let monitor: ServerMonitor
    let onShowSettings: () -> Void

    @Environment(\.openURL) private var openURL
    /// A timeout can hide a missing local network permission.
    @State private var localNetworkDenied = false
    @State private var copied = false

    private var effectiveProblem: ConnectionProblem {
        localNetworkDenied ? .localNetworkDenied : problem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                // The color is in the symbol; the text stays readable.
                Label {
                    Text(effectiveProblem.title)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
                .font(.headline)
                Spacer(minLength: 8)
                Button(copied ? "Copied" : "Copy Details", action: copyDetails)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Copy diagnostic details without passwords or host name")
            }
            Text(effectiveProblem.advice(hasCredentials: monitor.config.username != nil))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            // Side by side when they fit, otherwise stacked (long German labels).
            ViewThatFits(in: .horizontal) {
                HStack { actions }
                VStack(alignment: .leading) { actions }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(
            .orange.opacity(0.1), in: ConcentricRectangle(corners: .concentric(minimum: .fixed(8)), isUniform: true)
        )
        .task(id: problem) {
            localNetworkDenied = false
            if problem.mayBeLocalNetworkPermission {
                localNetworkDenied = await LocalNetworkCheck.isDenied(for: monitor.config.url) == true
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    @ViewBuilder
    private var actions: some View {
        if effectiveProblem == .localNetworkDenied {
            Button("Open Privacy Settings") { openURL(LocalNetworkCheck.settingsURL) }
                .fixedSize()
        }
        if effectiveProblem.isFixedInSettings {
            Button("Server Settings…", action: onShowSettings)
                .fixedSize()
        }
        Button("Try Again") { monitor.refresh() }
            .fixedSize()
    }

    private func copyDetails() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let report = DiagnosticReport.make(for: monitor, includeHost: false, appVersion: version)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        copied = true
    }
}
