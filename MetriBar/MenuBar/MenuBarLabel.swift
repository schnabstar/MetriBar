import MetriBarKit
import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: model.center.health.symbolName)
            if let value {
                Text(value)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var value: String? {
        guard let monitor = model.menuBarMonitor, monitor.health != .offline else { return nil }
        switch model.preferences.menuBarValue {
        case .none: return nil
        case .cpu: return monitor.snapshot.cpu.map { Format.percent($0.value.total) }
        case .memory: return monitor.snapshot.memory.map { Format.percent($0.value.percent) }
        }
    }

    private var accessibilityText: String {
        let status = String(localized: "MetriBar, \(model.center.health.label)")
        return [status, value].compactMap { $0 }.joined(separator: ", ")
    }
}
