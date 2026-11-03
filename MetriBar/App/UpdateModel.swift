import Foundation
import MetriBarKit
import Observation

/// Checks GitHub for a newer MetriBar release, if the user allowed it.
///
/// Automatic checks run only while `startAutomaticChecks()` is active, which
/// `AppModel` ties to the "Check for updates" setting, and at most once a
/// day. "Check Now" and the menu command are user actions and always run.
/// Nothing is downloaded or installed; the app only points to the release.
@MainActor
@Observable
final class UpdateModel {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case failed(UpdateError)
    }

    private(set) var state: State
    private(set) var lastCheck: Date?
    private(set) var skippedVersion: String?

    @ObservationIgnored private let currentVersion: AppVersion
    @ObservationIgnored private let checker: UpdateChecker
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var schedule: Task<Void, Never>?

    private enum Keys {
        static let lastCheck = "updateLastCheck"
        static let available = "updateAvailable"
        static let skipped = "updateSkippedVersion"
    }

    init(currentVersion: AppVersion, transport: any HTTPTransport, defaults: UserDefaults) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        checker = UpdateChecker(currentVersion: currentVersion, transport: transport)
        lastCheck = defaults.object(forKey: Keys.lastCheck) as? Date
        skippedVersion = defaults.string(forKey: Keys.skipped)

        // Remember a found update across launches, until it is installed.
        let known = defaults.data(forKey: Keys.available).flatMap {
            try? JSONDecoder().decode(AvailableUpdate.self, from: $0)
        }
        if let known, known.appVersion > currentVersion {
            state = .available(known)
        } else {
            state = .idle
        }
    }

    /// The newer release, if there is one.
    var available: AvailableUpdate? {
        if case .available(let update) = state { update } else { nil }
    }

    /// The newer release unless the user skipped that version: what the
    /// menu bar window points out.
    var announced: AvailableUpdate? {
        available.flatMap { $0.version == skippedVersion ? nil : $0 }
    }

    var isChecking: Bool {
        state == .checking
    }

    // MARK: - Checking

    /// Starts the daily check: one soon after launch, then whenever a day
    /// has passed since the last one. Wake from sleep is covered because the
    /// loop looks at the clock every hour.
    func startAutomaticChecks() {
        guard schedule == nil else { return }
        schedule = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                await self?.checkIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func stopAutomaticChecks() {
        schedule?.cancel()
        schedule = nil
    }

    func checkIfDue(now: Date = Date()) async {
        guard UpdatePolicy.isDue(lastCheck: lastCheck, now: now) else { return }
        await check(userInitiated: false)
    }

    /// Checks now, whatever the setting and the last check. A user action
    /// also brings back a version that was skipped.
    func checkNow() async {
        await check(userInitiated: true)
    }

    private func check(userInitiated: Bool) async {
        guard state != .checking else { return }
        let before = state
        state = .checking

        let result = await checker.check()
        lastCheck = Date()
        defaults.set(lastCheck, forKey: Keys.lastCheck)

        switch result {
        case .available(let update):
            if userInitiated { setSkipped(nil) }
            state = .available(update)
            defaults.set(try? JSONEncoder().encode(update), forKey: Keys.available)
        case .upToDate:
            state = .upToDate
            defaults.removeObject(forKey: Keys.available)
        case .failed(let error):
            // A failed check says nothing about a release found earlier.
            if case .available = before, !userInitiated {
                state = before
            } else {
                state = .failed(error)
            }
        }
    }

    // MARK: - Skipping

    func skipAvailableVersion() {
        setSkipped(available?.version)
    }

    private func setSkipped(_ version: String?) {
        skippedVersion = version
        defaults.set(version, forKey: Keys.skipped)
    }

    #if DEBUG
        /// For screenshots: pretends a newer release was found.
        func showFakeUpdate() {
            state = .available(
                AvailableUpdate(
                    version: "99.0.0",
                    pageURL: URL(string: "https://github.com/schnabstar/MetriBar/releases/tag/v99.0.0")!,
                    diskImageURL: nil))
        }
    #endif
}
