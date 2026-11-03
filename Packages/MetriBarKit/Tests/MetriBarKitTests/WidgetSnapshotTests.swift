import Foundation
import Testing

@testable import MetriBarKit

@MainActor
struct WidgetSnapshotTests {
    let clock = ManualClock()
    let server = FixtureServer()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "WidgetSnapshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sample(health: WidgetSnapshot.Health = .ok, cpu: Double? = 12, name: String = "NAS") -> WidgetSnapshot
    {
        WidgetSnapshot(
            generated: now,
            servers: [
                WidgetSnapshot.Server(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: name, health: health, cpu: cpu,
                    memory: 48, disk: 20.4, temperature: 52, updated: now)
            ])
    }

    // MARK: - Store

    @Test func writesAndReadsTheSnapshot() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.read() == nil)

        let snapshot = sample()
        try store.write(snapshot)
        #expect(store.read() == snapshot)

        // The newer one replaces it.
        try store.write(sample(health: .critical))
        #expect(store.read()?.overallHealth == .critical)

        store.remove()
        #expect(store.read() == nil)
    }

    @Test func unreadableOrNewerFilesGiveNothing() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: WidgetSnapshotStore.fileName)
        let store = WidgetSnapshotStore(directory: directory)

        try Data("not json".utf8).write(to: file)
        #expect(store.read() == nil)

        let future =
            #"{"version":\#(WidgetSnapshot.currentVersion + 1),"generated":"2026-11-05T10:00:00Z","servers":[]}"#
        try Data(future.utf8).write(to: file)
        #expect(store.read() == nil)

        let current = #"{"version":\#(WidgetSnapshot.currentVersion),"generated":"2026-11-05T10:00:00Z","servers":[]}"#
        try Data(current.utf8).write(to: file)
        #expect(store.read()?.servers.isEmpty == true)
    }

    // MARK: - Format

    @Test func decodesTolerantly() throws {
        let json = """
            {"version":1,"generated":"2026-11-05T10:00:00Z","servers":[
              {"id":"11111111-1111-1111-1111-111111111111","name":"Pi","health":"exploding","cpu":"fast"},
              {"name":"no id"}
            ]}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // One server without an id makes the whole file invalid: that is a broken file.
        #expect(throws: (any Error).self) { try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8)) }

        let ok =
            #"{"version":1,"generated":"2026-11-05T10:00:00Z","servers":[{"id":"11111111-1111-1111-1111-111111111111","health":"exploding","cpu":"fast","memory":40}]}"#
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(ok.utf8))
        let server = try #require(snapshot.servers.first)
        #expect(server.health == .unknown)
        #expect(server.cpu == nil)
        #expect(server.memory == 40)
        #expect(server.name.isEmpty)
    }

    @Test func overallHealthIsTheMostSeriousOne() {
        func server(_ health: WidgetSnapshot.Health) -> WidgetSnapshot.Server {
            WidgetSnapshot.Server(id: UUID(), name: "x", health: health)
        }
        #expect(WidgetSnapshot(generated: now, servers: []).overallHealth == .unknown)
        #expect(WidgetSnapshot(generated: now, servers: [server(.ok), server(.warning)]).overallHealth == .warning)
        #expect(
            WidgetSnapshot(generated: now, servers: [server(.critical), server(.warning)]).overallHealth == .critical)
        #expect(
            WidgetSnapshot(generated: now, servers: [server(.critical), server(.offline)]).overallHealth == .offline)
    }

    @Test func staleValuesAreRecognized() {
        var server = WidgetSnapshot.Server(id: UUID(), name: "x", health: .ok, updated: now)
        #expect(!server.isStale(now: now.addingTimeInterval(WidgetSnapshot.staleAfter)))
        #expect(server.isStale(now: now.addingTimeInterval(WidgetSnapshot.staleAfter + 1)))
        server.updated = nil
        #expect(server.isStale(now: now))
    }

    // MARK: - Building

    private func connectedMonitor(_ config: ServerConfig) async -> ServerMonitor {
        let monitor = ServerMonitor(config: config, client: server.client(), clock: clock)
        monitor.setExtraBackgroundFeeds([.storage])
        monitor.start()
        await waitUntil("monitor connected") { monitor.snapshot.fileSystems != nil }
        return monitor
    }

    @Test func buildsFromTheMonitors() async throws {
        let config = ServerConfig(name: "NAS", url: URL(string: "https://nas.example.com")!)
        let monitor = await connectedMonitor(config)
        defer { monitor.stop() }

        let snapshot = WidgetSnapshot.make(from: [monitor], now: now)
        let entry = try #require(snapshot.servers.first)
        #expect(snapshot.servers.count == 1)
        #expect(entry.id == config.id)
        #expect(entry.name == "NAS")
        #expect(entry.health == .ok)
        #expect(entry.cpu == monitor.snapshot.cpu?.value.total)
        #expect(entry.memory == monitor.snapshot.memory?.value.percent)
        #expect(entry.disk != nil)
        #expect(entry.temperature == 52)
        #expect(entry.updated == monitor.lastSuccess)
        #expect(snapshot.generated == now)
    }

    @Test func leavesOutServersThatAreTurnedOff() async {
        var off = ServerConfig(name: "Off", url: URL(string: "https://off.example.com")!)
        off.isEnabled = false
        let monitor = ServerMonitor(config: off, client: server.client(), clock: clock)
        #expect(WidgetSnapshot.make(from: [monitor], now: now).servers.isEmpty)
    }

    @Test func anUnreadableServerHasNoValues() async throws {
        let monitor = await connectedMonitor(ServerConfig(name: "NAS", url: URL(string: "https://nas.example.com")!))
        defer { monitor.stop() }
        server.goOffline()
        // Three failed polls in a row make the server unreadable. Each one is
        // waited for, so the test does not depend on how fast the machine is.
        for failures in 1...3 {
            await waitUntil("monitor waits for the next attempt") { !clock.pendingDelays.isEmpty }
            clock.advance(by: clock.pendingDelays.first ?? .seconds(60))
            await waitUntil("failure \(failures) recorded") { monitor.consecutiveFailures >= failures }
        }
        await waitUntil("offline") { monitor.health == .offline }
        let entry = try #require(WidgetSnapshot.make(from: [monitor], now: now).servers.first)
        #expect(entry.health == .offline)
        #expect(entry.cpu == nil && entry.memory == nil && entry.disk == nil && entry.temperature == nil)
    }

    /// The file is read by another process and lies on disk: nothing secret in it.
    @Test func containsNoSecretsAndNoAddresses() async throws {
        let config = ServerConfig(
            name: "NAS", url: URL(string: "https://secret-host.internal.example:61208/glances")!,
            username: "admin-user",
            pinnedCertificate: CertificateFingerprint(String(repeating: "ab", count: 32)))
        let monitor = await connectedMonitor(config)
        defer { monitor.stop() }

        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        try store.write(WidgetSnapshot.make(from: [monitor], now: now))
        let text = try String(contentsOf: directory.appending(path: WidgetSnapshotStore.fileName), encoding: .utf8)

        for forbidden in [
            "secret-host", "internal.example", "61208", "/glances", "admin-user", "glances-host", "username",
            "password",
            "url", "http", String(repeating: "ab", count: 8), "containers", "command",
        ] {
            #expect(!text.localizedCaseInsensitiveContains(forbidden), "\(forbidden) is in the widget file")
        }
        #expect(text.contains("NAS"))
    }

    // MARK: - When to write and reload

    private let policy = WidgetUpdatePolicy()

    @Test func theFirstSnapshotIsWrittenAndReloaded() {
        #expect(
            policy.decide(previous: nil, next: sample(), lastWrite: nil, lastReload: nil, now: now) == .writeAndReload)
    }

    @Test func aChangedStateReloadsAtOnceButNotTooOften() {
        let before = sample()
        let after = sample(health: .critical)
        #expect(
            policy.decide(
                previous: before, next: after, lastWrite: now.addingTimeInterval(-40),
                lastReload: now.addingTimeInterval(-40), now: now) == .writeAndReload)
        // Reloaded a moment ago: only the file is written.
        #expect(
            policy.decide(
                previous: before, next: after, lastWrite: now.addingTimeInterval(-10),
                lastReload: now.addingTimeInterval(-10), now: now) == .write)
    }

    @Test func aRenamedOrAddedServerCountsAsAChange() {
        let before = sample()
        #expect(
            policy.decide(
                previous: before, next: sample(name: "Pi"), lastWrite: now.addingTimeInterval(-100),
                lastReload: now.addingTimeInterval(-100), now: now) == .writeAndReload)
        var more = before
        more.servers.append(WidgetSnapshot.Server(id: UUID(), name: "Second", health: .ok))
        #expect(
            policy.decide(
                previous: before, next: more, lastWrite: now.addingTimeInterval(-100),
                lastReload: now.addingTimeInterval(-100), now: now) == .writeAndReload)
    }

    @Test func valuesAreWrittenEveryMinuteAndReloadedEveryFive() {
        let before = sample(cpu: 12)
        let moved = sample(cpu: 40)
        // 30 s since the last write: nothing yet.
        #expect(
            policy.decide(
                previous: before, next: moved, lastWrite: now.addingTimeInterval(-30),
                lastReload: now.addingTimeInterval(-30), now: now) == .nothing)
        // A minute: the file, no reload.
        #expect(
            policy.decide(
                previous: before, next: moved, lastWrite: now.addingTimeInterval(-61),
                lastReload: now.addingTimeInterval(-61), now: now) == .write)
        // Five minutes: reload too.
        #expect(
            policy.decide(
                previous: before, next: moved, lastWrite: now.addingTimeInterval(-61),
                lastReload: now.addingTimeInterval(-301), now: now) == .writeAndReload)
    }

    @Test func smallChangesAreNotWorthIt() {
        let before = sample(cpu: 12)
        let barely = sample(cpu: 12.4)
        #expect(
            policy.decide(
                previous: before, next: barely, lastWrite: now.addingTimeInterval(-120),
                lastReload: now.addingTimeInterval(-120), now: now) == .nothing)
    }

    @Test func aQuietSnapshotIsRefreshedEveryFiveMinutesSoItDoesNotLookOld() {
        let before = sample()
        #expect(
            policy.decide(
                previous: before, next: before, lastWrite: now.addingTimeInterval(-301),
                lastReload: now.addingTimeInterval(-301), now: now) == .writeAndReload)
        #expect(
            policy.decide(
                previous: before, next: before, lastWrite: now.addingTimeInterval(-200),
                lastReload: now.addingTimeInterval(-200), now: now) == .nothing)
    }
}
