import Foundation
import Testing

@testable import MetriBarKit

/// `ServerSnapshot.conditions` against the real fixtures.
struct ConditionTests {
    private func decode<Response: Decodable>(_ type: Response.Type, _ fixture: String) throws -> Response {
        try GlancesClient.decode(Response.self, from: Fixture.data(fixture))
    }

    private func snapshot() throws -> ServerSnapshot {
        var snapshot = ServerSnapshot()
        snapshot.cpu = try decode(Reading<CPU>.self, "cpu")
        snapshot.memory = try decode(Reading<Memory>.self, "mem")
        snapshot.load = try decode(Reading<Load>.self, "load")
        snapshot.containers = try decode(ItemCollection<ContainerInfo>.self, "containers")
        snapshot.sensors = try decode(ItemCollection<Sensor>.self, "sensors")
        snapshot.fileSystems = try decode(ItemCollection<FileSystem>.self, "fs")
        return snapshot
    }

    @Test func listsTheWatchedValuesWithTheirValues() throws {
        let conditions = try snapshot().conditions
        let cpu = try #require(conditions.first { $0.kind == .cpu })
        #expect(cpu.level == .ok)
        #expect(cpu.value != nil)
        #expect(conditions.first { $0.kind == .memory }?.value != nil)
        #expect(conditions.first { $0.kind == .load }?.value != nil)

        let mounts = conditions.filter { $0.kind == .fileSystem }.compactMap(\.item)
        #expect(mounts.contains("/mnt/volume-01"))
        #expect(conditions.first { $0.item == "/mnt/volume-01" }?.value == 20.4)

        #expect(conditions.contains { $0.kind == .container })
        // Only temperatures; the fan is not one.
        let sensors = conditions.filter { $0.kind == .sensor }.compactMap(\.item)
        #expect(sensors.contains("Composite"))
        #expect(!sensors.contains("pwmfan 0"))
    }

    @Test func missingFeedsGiveNoConditions() {
        #expect(ServerSnapshot().conditions.isEmpty)
    }

    @Test func levelsComeFromGlances() throws {
        var snapshot = try snapshot()
        snapshot.cpu?.levels["total"] = LevelInfo(level: .critical, prominent: true)
        snapshot.memory?.levels["percent"] = LevelInfo(level: .warning, prominent: true)
        let conditions = snapshot.conditions
        #expect(conditions.first { $0.kind == .cpu }?.level == .critical)
        #expect(conditions.first { $0.kind == .memory }?.level == .warning)
    }

    @Test func sensorsUseHardwareThresholdsAndReportedLevels() throws {
        var snapshot = try snapshot()
        // Composite: warning at 82, critical at 84.
        var items = try #require(snapshot.sensors?.items)
        let index = try #require(items.firstIndex { $0.label == "Composite" })
        items[index].value = 85
        snapshot.sensors?.items = items
        let conditions = snapshot.conditions
        #expect(conditions.first { $0.item == "Composite" }?.level == .critical)
        // No thresholds: the level Glances reports counts (careful in the fixture).
        #expect(conditions.first { $0.item == "cpu_thermal 0" }?.level == .careful)
    }

    @Test func unhealthyContainersAreAWarning() throws {
        var snapshot = try snapshot()
        var items = try #require(snapshot.containers?.items)
        let name = try #require(items.first?.name)
        items[0].status = "unhealthy"
        snapshot.containers?.items = items
        #expect(snapshot.conditions.first { $0.item == name }?.level == .warning)
        #expect(snapshot.hasUnhealthyContainers)
    }

    @Test func containerLevelsAreTheWorstOfTheirFields() throws {
        var snapshot = try snapshot()
        let name = try #require(snapshot.containers?.items.first?.name)
        snapshot.containers?.levels[name] = [
            "cpu_percent": LevelInfo(level: .ok, prominent: false),
            "memory_percent": LevelInfo(level: .critical, prominent: false),
        ]
        #expect(snapshot.conditions.first { $0.item == name }?.level == .critical)
    }

    @Test func fileSystemLevelsAreTheWorstOfTheirFields() throws {
        var snapshot = try snapshot()
        snapshot.fileSystems?.levels["/mnt/volume-02"] = ["percent": LevelInfo(level: .warning, prominent: true)]
        #expect(snapshot.conditions.first { $0.item == "/mnt/volume-02" }?.level == .warning)
        #expect(snapshot.conditions.first { $0.item == "/mnt/volume-01" }?.level != .warning)
    }

    /// The icon and the notifications agree about everything but file systems.
    @Test func conditionsAndWorstLevelAgree() throws {
        var snapshot = try snapshot()
        snapshot.cpu?.levels["total"] = LevelInfo(level: .critical, prominent: true)
        let worst = snapshot.conditions.filter { $0.kind != .fileSystem }.map(\.level).max()
        #expect(worst == snapshot.worstLevel)
    }
}
