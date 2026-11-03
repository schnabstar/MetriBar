import Foundation
import Testing

@testable import MetriBarKit

struct AlertEvaluatorTests {
    private let server = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func settings(hold: Int = 120, threshold: NotificationSettings.Threshold = .warning) -> NotificationSettings
    {
        var settings = NotificationSettings()
        settings.isEnabled = true
        settings.holdSeconds = hold
        settings.threshold = threshold
        return settings
    }

    private func observe(
        _ level: Level, kind: Condition.Kind = .cpu, item: String? = nil, offline: Bool = false
    ) -> ServerObservation {
        ServerObservation(
            serverID: server, serverName: "NAS", isOffline: offline,
            conditions: offline ? [] : [Condition(kind, item: item, level: level, value: 90)])
    }

    private func run(
        _ evaluator: inout AlertEvaluator, _ observation: ServerObservation, at seconds: TimeInterval
    ) -> [AlertNotice.Event] {
        evaluator.evaluate(observation, now: start.addingTimeInterval(seconds), calendar: calendar).map(\.event)
    }

    // MARK: - Hold time

    @Test func reportsAfterTheHoldTime() {
        var evaluator = AlertEvaluator(settings: settings(hold: 120))
        #expect(run(&evaluator, observe(.critical), at: 0) == [])
        #expect(run(&evaluator, observe(.critical), at: 119) == [])
        #expect(run(&evaluator, observe(.critical), at: 120) == [.raised])
        #expect(run(&evaluator, observe(.critical), at: 135) == [])
    }

    @Test func aShortSpikeIsNotReported() {
        var evaluator = AlertEvaluator(settings: settings(hold: 120))
        #expect(run(&evaluator, observe(.critical), at: 0) == [])
        #expect(run(&evaluator, observe(.critical), at: 60) == [])
        #expect(run(&evaluator, observe(.ok), at: 90) == [])
        // The count starts anew.
        #expect(run(&evaluator, observe(.critical), at: 100) == [])
        #expect(run(&evaluator, observe(.critical), at: 200) == [])
        #expect(run(&evaluator, observe(.critical), at: 220) == [.raised])
    }

    @Test func zeroHoldTimeReportsAtOnce() {
        var evaluator = AlertEvaluator(settings: settings(hold: 0))
        #expect(run(&evaluator, observe(.warning), at: 0) == [.raised])
    }

    @Test func noticeCarriesTheConditionAndTheServer() {
        var evaluator = AlertEvaluator(settings: settings(hold: 0))
        let notices = evaluator.evaluate(observe(.critical, kind: .fileSystem, item: "/mnt/data"), now: start)
        #expect(notices.count == 1)
        #expect(notices.first?.serverID == server)
        #expect(notices.first?.serverName == "NAS")
        #expect(notices.first?.condition == Condition(.fileSystem, item: "/mnt/data", level: .critical, value: 90))
    }

    // MARK: - Threshold

    @Test func levelsBelowTheChosenOneAreIgnored() {
        var warning = AlertEvaluator(settings: settings(hold: 0, threshold: .warning))
        #expect(run(&warning, observe(.careful), at: 0) == [])
        #expect(run(&warning, observe(.unknown), at: 10) == [])
        #expect(run(&warning, observe(.warning), at: 20) == [.raised])

        var critical = AlertEvaluator(settings: settings(hold: 0, threshold: .critical))
        #expect(run(&critical, observe(.warning), at: 0) == [])
        #expect(run(&critical, observe(.critical), at: 10) == [.raised])
    }

    // MARK: - Escalation

    @Test func aWorseProblemIsReportedAtOnce() {
        var evaluator = AlertEvaluator(settings: settings(hold: 120))
        _ = run(&evaluator, observe(.warning), at: 0)
        #expect(run(&evaluator, observe(.warning), at: 120) == [.raised])
        #expect(run(&evaluator, observe(.critical), at: 130) == [.escalated])
        #expect(run(&evaluator, observe(.critical), at: 145) == [])
    }

    @Test func aBetterProblemIsNotReported() {
        var evaluator = AlertEvaluator(settings: settings(hold: 0))
        #expect(run(&evaluator, observe(.critical), at: 0) == [.raised])
        #expect(run(&evaluator, observe(.warning), at: 10) == [])
        // Getting worse again counts as new.
        #expect(run(&evaluator, observe(.critical), at: 20) == [.escalated])
    }

    @Test func criticalAfterTheHoldTimeNeedsNoSecondWait() {
        var evaluator = AlertEvaluator(settings: settings(hold: 120))
        _ = run(&evaluator, observe(.warning), at: 0)
        #expect(run(&evaluator, observe(.critical), at: 125) == [.raised])
    }

    // MARK: - Recovery

    @Test func recoveryIsReportedOnlyWhenAskedFor() {
        var quiet = AlertEvaluator(settings: settings(hold: 0))
        _ = run(&quiet, observe(.critical), at: 0)
        #expect(run(&quiet, observe(.ok), at: 10) == [])

        var asked = settings(hold: 0)
        asked.notifiesRecovery = true
        var evaluator = AlertEvaluator(settings: asked)
        _ = run(&evaluator, observe(.critical), at: 0)
        #expect(run(&evaluator, observe(.ok), at: 10) == [.recovered])
        #expect(run(&evaluator, observe(.ok), at: 25) == [])
    }

    @Test func recoveryOfAnUnreportedProblemIsNoNews() {
        var asked = settings(hold: 120)
        asked.notifiesRecovery = true
        var evaluator = AlertEvaluator(settings: asked)
        _ = run(&evaluator, observe(.critical), at: 0)
        #expect(run(&evaluator, observe(.ok), at: 30) == [])
    }

    // MARK: - Cooldown

    @Test func theSameConditionIsNotReportedAgainWithinTheCooldown() {
        var evaluator = AlertEvaluator(settings: settings(hold: 0))
        #expect(run(&evaluator, observe(.critical), at: 0) == [.raised])
        #expect(run(&evaluator, observe(.ok), at: 60) == [])
        #expect(run(&evaluator, observe(.critical), at: 120) == [])
        // Still the same problem after the cooldown: now it is reported.
        #expect(run(&evaluator, observe(.critical), at: AlertEvaluator.cooldown + 1) == [.raised])
    }

    @Test func conditionsAreIndependent() {
        var evaluator = AlertEvaluator(settings: settings(hold: 0))
        let both = ServerObservation(
            serverID: server, serverName: "NAS", isOffline: false,
            conditions: [
                Condition(.cpu, level: .critical), Condition(.fileSystem, item: "/a", level: .warning),
                Condition(.fileSystem, item: "/b", level: .ok),
            ])
        let notices = evaluator.evaluate(both, now: start)
        #expect(notices.map(\.condition.kind) == [.cpu, .fileSystem])
        #expect(Set(notices.map(\.id)).count == 2)
    }

    @Test func aRemovedItemIsNotARecovery() {
        var asked = settings(hold: 0)
        asked.notifiesRecovery = true
        var evaluator = AlertEvaluator(settings: asked)
        #expect(run(&evaluator, observe(.critical, kind: .container, item: "db"), at: 0) == [.raised])
        let gone = ServerObservation(serverID: server, serverName: "NAS", isOffline: false, conditions: [])
        #expect(evaluator.evaluate(gone, now: start.addingTimeInterval(10)).isEmpty)
    }

    // MARK: - Offline

    @Test func offlineServersAreReportedAfterTheHoldTimeAndWhenBack() {
        var evaluator = AlertEvaluator(settings: settings(hold: 120))
        #expect(run(&evaluator, observe(.ok, offline: true), at: 0) == [])
        #expect(run(&evaluator, observe(.ok, offline: true), at: 120) == [.offline])
        #expect(run(&evaluator, observe(.ok, offline: true), at: 200) == [])
        // Back, although recovery notices are off.
        #expect(run(&evaluator, observe(.ok), at: 300) == [.backOnline])
    }

    @Test func aServerThatWasNeverReportedOfflineIsNotReportedBack() {
        var evaluator = AlertEvaluator(settings: settings(hold: 120))
        _ = run(&evaluator, observe(.ok, offline: true), at: 0)
        #expect(run(&evaluator, observe(.ok), at: 30) == [])
    }

    @Test func offlineNoticesCanBeTurnedOff() {
        var turnedOff = settings(hold: 0)
        turnedOff.notifiesOffline = false
        var evaluator = AlertEvaluator(settings: turnedOff)
        #expect(run(&evaluator, observe(.ok, offline: true), at: 0) == [])
        #expect(run(&evaluator, observe(.ok, offline: true), at: 600) == [])
    }

    @Test func valuesOfAnOfflineServerAreNotLookedAt() {
        var asked = settings(hold: 0)
        asked.notifiesRecovery = true
        var evaluator = AlertEvaluator(settings: asked)
        #expect(run(&evaluator, observe(.critical), at: 0) == [.raised])
        // Offline for a while: the old critical value is neither a recovery nor new.
        #expect(run(&evaluator, observe(.ok, offline: true), at: 10) == [.offline])
        // Still critical when it is back: no second notice, the cooldown holds.
        #expect(run(&evaluator, observe(.critical), at: 20) == [.backOnline])
    }

    // MARK: - Resume

    @Test func offlineServersAreIgnoredRightAfterWaking() {
        var evaluator = AlertEvaluator(settings: settings(hold: 0))
        evaluator.noteResume(now: start)
        #expect(run(&evaluator, observe(.ok, offline: true), at: 10) == [])
        #expect(run(&evaluator, observe(.ok, offline: true), at: AlertEvaluator.resumeGrace) == [.offline])
    }

    @Test func waitingProblemsStartCountingAnewAfterWaking() {
        var evaluator = AlertEvaluator(settings: settings(hold: 120))
        _ = run(&evaluator, observe(.critical), at: 0)
        evaluator.noteResume(now: start.addingTimeInterval(3600))
        // Without the reset the hour-old start would report it at once.
        #expect(run(&evaluator, observe(.critical), at: 3601) == [])
        #expect(run(&evaluator, observe(.critical), at: 3721) == [.raised])
    }

    // MARK: - Quiet hours

    @Test func quietHoursHoldBackNoticesAndReleaseThemWhenTheyEnd() {
        var quiet = settings(hold: 0)
        quiet.quietHours = QuietHours(isEnabled: true, startMinute: 22 * 60, endMinute: 7 * 60)
        var evaluator = AlertEvaluator(settings: quiet)
        let midnight = calendar.startOfDay(for: start).addingTimeInterval(24 * 3600)
        let atNight = midnight.addingTimeInterval(3600)
        let inTheMorning = midnight.addingTimeInterval(7 * 3600)

        #expect(evaluator.evaluate(observe(.critical), now: atNight, calendar: calendar).isEmpty)
        #expect(
            evaluator.evaluate(observe(.critical), now: atNight.addingTimeInterval(3600), calendar: calendar).isEmpty)
        // Still there at seven: reported then.
        #expect(evaluator.evaluate(observe(.critical), now: inTheMorning, calendar: calendar).map(\.event) == [.raised])
    }

    @Test func quietHoursSpanMidnightAndHonorTheirEnds() {
        let hours = QuietHours(isEnabled: true, startMinute: 22 * 60, endMinute: 7 * 60)
        let day = calendar.startOfDay(for: start)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
        #expect(hours.contains(at(22), calendar: calendar))
        #expect(hours.contains(at(23, 59), calendar: calendar))
        #expect(hours.contains(at(0), calendar: calendar))
        #expect(hours.contains(at(6, 59), calendar: calendar))
        #expect(!hours.contains(at(7), calendar: calendar))
        #expect(!hours.contains(at(12), calendar: calendar))
        #expect(!hours.contains(at(21, 59), calendar: calendar))

        let daytime = QuietHours(isEnabled: true, startMinute: 12 * 60, endMinute: 13 * 60)
        #expect(daytime.contains(at(12, 30), calendar: calendar))
        #expect(!daytime.contains(at(13), calendar: calendar))

        #expect(!QuietHours(isEnabled: false, startMinute: 0, endMinute: 1439).contains(at(3), calendar: calendar))
        #expect(!QuietHours(isEnabled: true, startMinute: 600, endMinute: 600).contains(at(10), calendar: calendar))
    }

    @Test func aProblemThatGetsWorseInTheQuietIsReportedAfterwards() {
        var quiet = settings(hold: 0)
        quiet.quietHours = QuietHours(isEnabled: true, startMinute: 22 * 60, endMinute: 7 * 60)
        var evaluator = AlertEvaluator(settings: quiet)
        let day = calendar.startOfDay(for: start).addingTimeInterval(24 * 3600)
        #expect(
            evaluator.evaluate(observe(.warning), now: day.addingTimeInterval(12 * 3600), calendar: calendar).count == 1
        )
        #expect(
            evaluator.evaluate(observe(.critical), now: day.addingTimeInterval(23 * 3600), calendar: calendar).isEmpty)
        let events = evaluator.evaluate(observe(.critical), now: day.addingTimeInterval(31 * 3600), calendar: calendar)
        #expect(events.map(\.event) == [.escalated])
    }

    // MARK: - Outdated values

    private func observe(
        _ level: Level, kind: Condition.Kind, unavailable: Set<Condition.Kind>
    ) -> ServerObservation {
        ServerObservation(
            serverID: server, serverName: "NAS", isOffline: false,
            conditions: [Condition(kind, item: kind == .fileSystem ? "/mnt" : nil, level: level, value: 90)],
            unavailable: unavailable)
    }

    @Test func outdatedValuesDoNotAdvanceTheTimer() {
        var evaluator = AlertEvaluator(settings: settings(hold: 120))
        #expect(run(&evaluator, observe(.critical, kind: .fileSystem, unavailable: []), at: 0) == [])
        // The feed fails for a long time; its last value is still critical.
        #expect(run(&evaluator, observe(.critical, kind: .fileSystem, unavailable: [.fileSystem]), at: 100) == [])
        #expect(run(&evaluator, observe(.critical, kind: .fileSystem, unavailable: [.fileSystem]), at: 500) == [])
        // Fresh again: counting starts anew, the old start is not used.
        #expect(run(&evaluator, observe(.critical, kind: .fileSystem, unavailable: []), at: 520) == [])
        #expect(run(&evaluator, observe(.critical, kind: .fileSystem, unavailable: []), at: 639) == [])
        #expect(run(&evaluator, observe(.critical, kind: .fileSystem, unavailable: []), at: 640) == [.raised])
    }

    @Test func outdatedValuesAreNeitherARecoveryNorANewProblem() {
        var asked = settings(hold: 0)
        asked.notifiesRecovery = true
        var evaluator = AlertEvaluator(settings: asked)
        #expect(run(&evaluator, observe(.critical, kind: .fileSystem, unavailable: []), at: 0) == [.raised])
        // Nothing is known while the feed fails: not even a gone condition is a recovery.
        let none = ServerObservation(
            serverID: server, serverName: "NAS", isOffline: false, conditions: [], unavailable: [.fileSystem])
        #expect(evaluator.evaluate(none, now: start.addingTimeInterval(10)).isEmpty)
        // Still critical afterwards: it was reported, not reported again.
        #expect(run(&evaluator, observe(.critical, kind: .fileSystem, unavailable: []), at: 20) == [])
        // Now it really is over.
        #expect(run(&evaluator, observe(.ok, kind: .fileSystem, unavailable: []), at: 30) == [.recovered])
    }

    @Test func outdatedKindsDoNotAffectOtherKinds() {
        var evaluator = AlertEvaluator(settings: settings(hold: 0))
        let both = ServerObservation(
            serverID: server, serverName: "NAS", isOffline: false,
            conditions: [Condition(.cpu, level: .critical), Condition(.fileSystem, item: "/mnt", level: .critical)],
            unavailable: [.fileSystem])
        let notices = evaluator.evaluate(both, now: start)
        #expect(notices.map(\.condition.kind) == [.cpu])
    }

    // MARK: - Servers

    @Test func serversDoNotInfluenceEachOther() {
        var evaluator = AlertEvaluator(settings: settings(hold: 0))
        let other = ServerObservation(
            serverID: UUID(), serverName: "Pi", isOffline: false, conditions: [Condition(.cpu, level: .critical)])
        #expect(run(&evaluator, observe(.critical), at: 0) == [.raised])
        #expect(evaluator.evaluate(other, now: start).count == 1)
    }

    @Test func forgetsServersThatAreNotListed() {
        var evaluator = AlertEvaluator(settings: settings(hold: 0))
        #expect(run(&evaluator, observe(.critical), at: 0) == [.raised])
        evaluator.forget(except: [])
        // Forgotten, so not within the cooldown any more.
        #expect(run(&evaluator, observe(.critical), at: 10) == [.raised])
    }
}
