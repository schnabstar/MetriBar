import AppKit
import MetriBarKit
import SwiftUI

/// Menu bar commands, so every keyboard shortcut is discoverable in a menu.
struct AppCommands: Commands {
    let model: AppModel
    @FocusedValue(\.dashboardMonitor) private var monitor

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MetriBar", action: AboutPanel.show)
        }
        CommandGroup(before: .toolbar) {
            Group {
                ForEach(DashboardSection.allCases) { section in
                    Button(section.title) { model.dashboardSection = section }
                        .keyboardShortcut(KeyEquivalent(section.shortcut), modifiers: .command)
                }
                Divider()
                Button("Refresh") { monitor?.refresh() }
                    .keyboardShortcut("r")
            }
            .disabled(monitor == nil)
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("MetriBar Source Code") { NSWorkspace.shared.open(AboutPanel.sourceURL) }
            Button("Report a Problem") { NSWorkspace.shared.open(AboutPanel.issuesURL) }
        }
    }
}

/// The standard About window. Name, icon, version and copyright come from
/// the Info.plist; the credits add links and the privacy note.
enum AboutPanel {
    static let sourceURL = URL(string: "https://github.com/schnabstar/MetriBar")!
    static let issuesURL = URL(string: "https://github.com/schnabstar/MetriBar/issues")!

    static func show() {
        NSApplication.shared.activate()
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let text = NSMutableAttributedString()
        func append(_ string: String, link: URL? = nil) {
            var attributes = attributes
            attributes[.link] = link
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        append(String(localized: "Glances 5 in your menu bar.") + "\n")
        append(String(localized: "Source Code"), link: sourceURL)
        append("  ·  ")
        append(String(localized: "Report a Problem"), link: issuesURL)
        append("\n\n" + String(localized: "MetriBar collects no data and has no telemetry.") + "\n")
        append(String(localized: "MetriBar is not affiliated with the Glances project."))
        return text
    }
}
