import SwiftUI

struct OnboardingView: View {
    let onAddServer: () -> Void
    let onTryDemo: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Welcome to MetriBar")
                .font(.title3.bold())
            Text("Add a server running Glances 5 to see its status in the menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Server…", action: onAddServer)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            Button("Try with Demo Data", action: onTryDemo)
                .buttonStyle(.link)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
