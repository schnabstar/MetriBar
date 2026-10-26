import SwiftUI

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("MetriBar")
                .font(.title2.bold())
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Glances 5 in your menu bar.")
            Link("github.com/schnabstar/MetriBar", destination: URL(string: "https://github.com/schnabstar/MetriBar")!)
            Text("Licensed under the Apache License 2.0. Not affiliated with the Glances project.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
