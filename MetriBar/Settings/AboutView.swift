import SwiftUI

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(verbatim: "MetriBar")
                .font(.title2.bold())
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Glances 5 in your menu bar.")
            HStack(spacing: 16) {
                Link("Source Code", destination: URL(string: "https://github.com/schnabstar/MetriBar")!)
                Link("Report a Problem", destination: URL(string: "https://github.com/schnabstar/MetriBar/issues")!)
            }
            Text("MetriBar collects no data and has no telemetry.")
                .font(.callout)
            Text("Licensed under the Apache License 2.0. MetriBar is not affiliated with the Glances project.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
