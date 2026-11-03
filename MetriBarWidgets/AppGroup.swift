import Foundation
import MetriBarKit

/// The data the app wrote for the widgets.
enum AppGroup {
    /// The shared container. `nil` if this build has no App Group.
    static var directory: URL? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "MetriBarAppGroup") as? String,
            !identifier.isEmpty
        else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func snapshot() -> WidgetSnapshot? {
        directory.flatMap { WidgetSnapshotStore(directory: $0).read() }
    }
}
