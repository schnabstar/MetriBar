import Foundation
import MetriBarKit
import OSLog
import Observation
import WidgetKit

/// Hands the state of the servers to the widgets.
///
/// The widget extension does not poll: it has no Keychain and no network
/// access, and a widget may only refresh a few dozen times a day. This
/// writes a small, secret-free `WidgetSnapshot` into the App Group
/// container and asks the widgets to reload when something changed. It
/// does so only while at least one widget or control of MetriBar exists on
/// this Mac; without one the file is deleted, so no server names lie around
/// for nothing.
@MainActor
@Observable
final class WidgetBridge {
    /// At least one widget or control of MetriBar is set up.
    private(set) var isActive = false

    /// Called when `isActive` changes: the file systems are fetched in the
    /// background only while widgets show them.
    @ObservationIgnored var onActiveChange: ((Bool) -> Void)?

    @ObservationIgnored private let store: WidgetSnapshotStore?
    @ObservationIgnored private let monitors: @MainActor () -> [ServerMonitor]
    @ObservationIgnored private let policy = WidgetUpdatePolicy()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var previous: WidgetSnapshot?
    @ObservationIgnored private var lastWrite: Date?
    @ObservationIgnored private var lastReload: Date?
    @ObservationIgnored private var lastActivityCheck: Date?
    @ObservationIgnored private static let logger = Logger(subsystem: "it.schnabel.MetriBar", category: "widgets")

    /// - Parameter monitors: The monitors to summarize.
    /// - Parameter directory: The App Group container; `nil` for a build
    ///   without an App Group, which then has no widgets.
    init(directory: URL?, monitors: @escaping @MainActor () -> [ServerMonitor]) {
        store = directory.map { WidgetSnapshotStore(directory: $0) }
        self.monitors = monitors
    }

    /// The App Group container, from the identifier in the Info.plist.
    static var groupDirectory: URL? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "MetriBarAppGroup") as? String,
            !identifier.isEmpty
        else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    #if DEBUG
        /// For checking the data flow without a widget on the desktop.
        @ObservationIgnored var debugForcesActivity = false
    #endif

    func start() {
        guard task == nil, store != nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() async {
        await refreshActivity()
        guard isActive, let store else { return }
        let now = Date()
        let next = WidgetSnapshot.make(from: monitors(), now: now)
        let action = policy.decide(
            previous: previous, next: next, lastWrite: lastWrite, lastReload: lastReload, now: now)
        guard action != .nothing else { return }
        do {
            try store.write(next)
        } catch {
            Self.logger.error("Could not write the widget data: \(error.localizedDescription, privacy: .public)")
            return
        }
        previous = next
        lastWrite = now
        if action == .writeAndReload {
            lastReload = now
            WidgetCenter.shared.reloadAllTimelines()
            // A control is not a timeline: it has to be asked separately, or it
            // keeps its old value until the user touches it.
            ControlCenter.shared.reloadControls(ofKind: WidgetKind.status)
        }
    }

    /// Asks the system whether any widget or control of MetriBar is set up,
    /// at most once a minute.
    private func refreshActivity() async {
        let now = Date()
        if let lastActivityCheck, now.timeIntervalSince(lastActivityCheck) < 60 { return }
        lastActivityCheck = now

        // Someone may have added only the control, which is no widget
        // configuration, or only widgets.
        let widgets = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        let controls = (try? await ControlCenter.shared.currentControls()) ?? []
        #if DEBUG
            let active = !widgets.isEmpty || !controls.isEmpty || debugForcesActivity
        #else
            let active = !widgets.isEmpty || !controls.isEmpty
        #endif
        guard active != isActive else { return }
        isActive = active
        Self.logger.notice("Widgets are \(active ? "in use" : "not in use", privacy: .public)")
        if !active {
            store?.remove()
            previous = nil
            lastWrite = nil
        }
        onActiveChange?(active)
    }
}
