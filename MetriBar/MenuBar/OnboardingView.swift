import SwiftUI

struct OnboardingView: View {
    let onAddServer: () -> Void
    let onTryDemo: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Welcome to MetriBar")
            } icon: {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
        } description: {
            Text("Add a server running Glances 5 to see its status in the menu bar.")
        } actions: {
            Button("Add Server…", action: onAddServer)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            Button("Try with Demo Data", action: onTryDemo)
                .buttonStyle(.link)
        }
    }
}
