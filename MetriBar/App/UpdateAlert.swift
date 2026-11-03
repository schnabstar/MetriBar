import AppKit
import MetriBarKit

/// The result of "Check for Updates…" from the app menu, which has no window
/// of its own to show it in.
@MainActor
enum UpdateAlert {
    static func check(using updates: UpdateModel) async {
        await updates.checkNow()
        NSApplication.shared.activate()

        let alert = NSAlert()
        switch updates.state {
        case .available(let update):
            alert.messageText = String(localized: "MetriBar \(update.version) is available")
            alert.informativeText = String(
                localized:
                    "You have MetriBar \(AppModel.currentVersion.description). MetriBar does not install updates by itself; download the new version and replace the app in your Applications folder."
            )
            alert.addButton(withTitle: String(localized: "Download"))
            alert.addButton(withTitle: String(localized: "Release Notes"))
            alert.addButton(withTitle: String(localized: "Later"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: NSWorkspace.shared.open(update.diskImageURL ?? update.pageURL)
            case .alertSecondButtonReturn: NSWorkspace.shared.open(update.pageURL)
            default: break
            }
        case .failed(let error):
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Could not check for updates")
            alert.informativeText = error.message
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
        default:
            alert.messageText = String(localized: "MetriBar is up to date")
            alert.informativeText = String(localized: "You have MetriBar \(AppModel.currentVersion.description).")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
        }
    }
}
