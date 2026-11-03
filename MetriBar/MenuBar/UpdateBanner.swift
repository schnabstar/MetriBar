import MetriBarKit
import SwiftUI

/// Points out a newer release in the menu bar window. The update is never
/// installed from here; the buttons open the release in the browser.
struct UpdateBanner: View {
    let update: AvailableUpdate
    let onSkip: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The color is in the symbol; the text stays readable.
            Label {
                Text("MetriBar \(update.version) is available")
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            }
            .font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack { actions }
                VStack(alignment: .leading) { actions }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            .blue.opacity(0.1), in: ConcentricRectangle(corners: .concentric(minimum: .fixed(8)), isUniform: true)
        )
    }

    @ViewBuilder
    private var actions: some View {
        Button("Download") { open(update.diskImageURL ?? update.pageURL) }
            .fixedSize()
        Button("Release Notes") { open(update.pageURL) }
            .fixedSize()
        Button("Skip This Version", action: onSkip)
            .fixedSize()
    }

    private func open(_ url: URL) {
        dismissingMenuBarWindow { openURL(url) }
    }
}
