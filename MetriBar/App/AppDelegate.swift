import AppKit

/// Receives `metribar:` addresses, which the widgets open. SwiftUI's
/// `onOpenURL` needs a window that is already open, and MetriBar's
/// windows are closed most of the time.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app once its model exists.
    @MainActor static var openURL: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { Self.openURL?(url) }
        }
    }
}
