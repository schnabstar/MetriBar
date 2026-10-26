import MetriBarKit
import SwiftUI

/// Shows the server certificate and lets the user trust a self-signed one
/// by pinning its fingerprint.
struct CertificateSection: View {
    let url: URL
    @Binding var pinned: CertificateFingerprint?

    @State private var info: CertificateInfo?
    @State private var problem: ConnectionProblem?
    @State private var isChecking = false

    var body: some View {
        Section {
            if let pinned {
                LabeledContent("Trusted certificate") {
                    Button("Stop Trusting") { self.pinned = nil }
                }
                fingerprintText(pinned)
            }
            HStack {
                Button("Check Certificate", action: check)
                    .disabled(isChecking)
                if isChecking { ProgressView().controlSize(.small) }
            }
            if let info {
                certificateDetails(info)
            } else if let problem {
                Text(problem.title).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Certificate")
        } footer: {
            Text(
                "For a self-signed certificate, compare the fingerprint with the one on the server before trusting it, for example: openssl x509 -in cert.pem -noout -fingerprint -sha256"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: url) {
            info = nil
            problem = nil
        }
    }

    @ViewBuilder
    private func certificateDetails(_ info: CertificateInfo) -> some View {
        if let subject = info.subject {
            LabeledContent("Issued to", value: subject)
        }
        LabeledContent("Status") {
            if info.isTrustedBySystem {
                Label("Trusted by macOS", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else if info.fingerprint == pinned {
                Label("Trusted by you", systemImage: "pin.fill").foregroundStyle(.green)
            } else {
                Label("Not trusted by macOS", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        fingerprintText(info.fingerprint)
        if !info.isTrustedBySystem, info.fingerprint != pinned {
            Button("Trust This Certificate") { pinned = info.fingerprint }
        }
    }

    private func fingerprintText(_ fingerprint: CertificateFingerprint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SHA-256 fingerprint").font(.caption).foregroundStyle(.secondary)
            Text(fingerprint.description)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func check() {
        isChecking = true
        info = nil
        problem = nil
        Task {
            do throws(GlancesError) {
                info = try await CertificateInspector.inspect(url, configuration: .metriBarConnectionTest)
            } catch {
                problem = ConnectionProblem(error)
            }
            isChecking = false
        }
    }
}
