import SwiftUI

/// Full-width rows with a hover highlight, like the rows at the bottom of
/// Control Center modules and other menu bar windows.
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }
}

extension ButtonStyle where Self == MenuRowButtonStyle {
    static var menuRow: MenuRowButtonStyle { MenuRowButtonStyle() }
}

private struct MenuRow: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isEnabled ? HierarchicalShapeStyle.primary : .tertiary)
            .background {
                if isEnabled, isHovered || configuration.isPressed {
                    // Concentric with the menu bar window where it touches its corners.
                    ConcentricRectangle(corners: .concentric(minimum: .fixed(6)))
                        .fill(.quaternary)
                }
            }
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }
}
