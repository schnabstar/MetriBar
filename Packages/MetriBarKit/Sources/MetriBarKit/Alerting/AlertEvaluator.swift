import Foundation

/// Something worth telling the user, produced by `AlertEvaluator`.
public struct AlertNotice: Sendable, Equatable, Identifiable {
    public enum Event: Sendable, Equatable {
        /// A value reached the chosen level and stayed there.
        case raised
        /// A reported problem got worse, for example from warning to critical.
        case escalated
        /// A reported problem is gone.
        case recovered
        /// The server cannot be read.
        case offline
        /// A server reported as offline can be read again.
        case backOnline
    }

    public var serverID: UUID
    public var serverName: String
    public var event: Event
    /// The condition with the level it has now: `ok` for `recovered` and
    /// `backOnline`.
    public var condition: Condition

    /// The same for every notice about the same condition, so a newer one
    /// can replace an older one on screen.
    public var id: String {
        "\(serverID.uuidString)/\(condition.kind.rawValue)/\(condition.item ?? "")"
    }

    public init(serverID: UUID, serverName: String, event: Event, condition: Condition) {
        self.serverID = serverID
        self.serverName = serverName
        self.event = event
        self.condition = condition
    }
}

/// What `AlertEvaluator` is told about one server at one moment.
public struct ServerObservation: Sendable {
    public var serverID: UUID
    public var serverName: String
    /// The server cannot be read. Its values are outdated then and not looked at.
    public var isOffline: Bool
    public var conditions: [Condition]
    /// Kinds whose values are outdated, for example because their feed
    /// failed. They are neither reported nor counted as recovered.
    public var unavailable: Set<Condition.Kind>

    public init(
        serverID: UUID, serverName: String, isOffline: Bool, conditions: [Condition],
        unavailable: Set<Condition.Kind> = []
    ) {
        self.serverID = serverID
        self.serverName = serverName
        self.isOffline = isOffline
        self.conditions = conditions
        self.unavailable = unavailable
    }
}

/// Decides which changes of a server's conditions become notifications.
///
/// A pure state machine: it has no clock and no side effects, the caller
/// passes `now`. Rules:
///
/// - A condition has to stay at or above the chosen level for the hold
///   time before it is reported, so a short spike is not.
/// - The same condition is reported at most once per `cooldown`, so a value
///   that hovers around its threshold does not produce a stream of
///   notifications.
/// - A reported problem that gets worse is reported again at once; a problem
///   that gets better is not.
/// - Recovery is reported only if asked for. A server that was reported
///   offline is always reported back online.
/// - During quiet hours nothing is reported and nothing is lost: a problem
///   that lasts beyond them is reported when they end.
/// - Values that are outdated (their feed failed) are not looked at: no
///   timer runs on them and nothing counts as recovered.
/// - After the Mac woke up or the network changed, offline servers are
///   ignored for a minute and waiting problems start counting anew, because
///   the values of before the sleep say nothing about now.
public struct AlertEvaluator: Sendable {
    public static let cooldown: TimeInterval = 15 * 60
    public static let resumeGrace: TimeInterval = 60

    public var settings: NotificationSettings

    private struct State {
        /// Since when the condition is at or above the chosen level.
        var since: Date?
        /// The level the user was told about, `nil` if they were not.
        var notifiedLevel: Level?
        var lastRaised: Date?
    }

    private var states: [ConditionKey: State] = [:]
    private var graceUntil: Date?

    public init(settings: NotificationSettings = NotificationSettings()) {
        self.settings = settings
    }

    /// Takes a look at one server.
    public mutating func evaluate(
        _ observation: ServerObservation, now: Date, calendar: Calendar = .current
    ) -> [AlertNotice] {
        let quiet = settings.quietHours.contains(now, calendar: calendar)
        var notices: [AlertNotice] = []

        func emit(_ event: AlertNotice.Event, _ condition: Condition) {
            notices.append(
                AlertNotice(
                    serverID: observation.serverID, serverName: observation.serverName, event: event,
                    condition: condition))
        }

        let offlineKey = ConditionKey(serverID: observation.serverID, kind: .offline, item: nil)

        if observation.isOffline {
            guard settings.notifiesOffline else { return [] }
            if let graceUntil, now < graceUntil { return [] }
            let condition = Condition(.offline, level: .critical)
            if step(offlineKey, active: .critical, now: now, quiet: quiet) != nil {
                emit(.offline, condition)
            }
            return notices
        }

        if step(offlineKey, active: .ok, now: now, quiet: quiet) != nil {
            emit(.backOnline, Condition(.offline, level: .ok))
        }

        // Outdated values neither start nor advance a timer. What was
        // reported stays reported, so the problem is not announced a second
        // time when fresh values show it again.
        var seen: Set<ConditionKey> = [offlineKey]
        for key in states.keys where key.serverID == observation.serverID && observation.unavailable.contains(key.kind)
        {
            states[key]?.since = nil
            seen.insert(key)
        }
        for condition in observation.conditions where !observation.unavailable.contains(condition.kind) {
            let key = ConditionKey(serverID: observation.serverID, kind: condition.kind, item: condition.item)
            seen.insert(key)
            let active = condition.level >= settings.threshold.level ? condition.level : .ok
            switch step(key, active: active, now: now, quiet: quiet) {
            case .raised?: emit(.raised, condition)
            case .escalated?: emit(.escalated, condition)
            case .recovered?: if settings.notifiesRecovery { emit(.recovered, condition) }
            case .back?, nil: break
            }
        }

        // A container that was removed or a sensor that disappeared is not
        // a recovery; its state is just dropped.
        for key in states.keys where key.serverID == observation.serverID && !seen.contains(key) {
            states[key] = nil
        }
        return notices
    }

    /// Call after the Mac woke up or the network changed.
    public mutating func noteResume(now: Date) {
        graceUntil = now.addingTimeInterval(Self.resumeGrace)
        for key in states.keys {
            states[key]?.since = nil
        }
    }

    /// Forgets everything about servers that are not in `serverIDs`, for
    /// example because they were removed or muted.
    public mutating func forget(except serverIDs: Set<UUID>) {
        for key in states.keys where !serverIDs.contains(key.serverID) {
            states[key] = nil
        }
    }

    // MARK: - State machine

    private enum Step {
        case raised, escalated, recovered, back
    }

    /// Moves one condition forward. `active` is its level if that is at or
    /// above the chosen level, otherwise `ok`.
    private mutating func step(_ key: ConditionKey, active: Level, now: Date, quiet: Bool) -> Step? {
        var state = states[key] ?? State()
        defer {
            let cooledDown = state.lastRaised.map { now.timeIntervalSince($0) >= Self.cooldown } ?? true
            if state.since == nil, state.notifiedLevel == nil, cooledDown {
                states[key] = nil
            } else {
                states[key] = state
            }
        }

        guard active > .ok else {
            state.since = nil
            guard state.notifiedLevel != nil else { return nil }
            // Told about it, so the end is news; during quiet hours it is not.
            state.notifiedLevel = nil
            guard !quiet else { return nil }
            return key.kind == .offline ? .back : .recovered
        }

        if state.since == nil { state.since = now }

        if let notified = state.notifiedLevel {
            if active < notified {
                state.notifiedLevel = active
            } else if active > notified, !quiet {
                state.notifiedLevel = active
                return .escalated
            }
            return nil
        }

        guard !quiet, let since = state.since, now.timeIntervalSince(since) >= settings.holdTime else { return nil }
        if let last = state.lastRaised, now.timeIntervalSince(last) < Self.cooldown { return nil }
        state.notifiedLevel = active
        state.lastRaised = now
        return .raised
    }
}
