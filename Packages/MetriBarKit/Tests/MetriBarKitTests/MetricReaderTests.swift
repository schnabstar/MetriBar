import Foundation
import Testing

@testable import MetriBarKit

/// `MetricReader` against the real fixtures.
struct MetricReaderTests {
    private func decode<Response: Decodable>(_ type: Response.Type, _ fixture: String) throws -> Response {
        try GlancesClient.decode(Response.self, from: Fixture.data(fixture))
    }

    private func snapshot() throws -> ServerSnapshot {
        var snapshot = ServerSnapshot()
        snapshot.cpu = try decode(Reading<CPU>.self, "cpu")
        snapshot.memory = try decode(Reading<Memory>.self, "mem")
        snapshot.swap = try decode(Reading<Swap>.self, "memswap")
        snapshot.load = try decode(Reading<Load>.self, "load")
        snapshot.sensors = try decode(ItemCollection<Sensor>.self, "sensors")
        snapshot.fileSystems = try decode(ItemCollection<FileSystem>.self, "fs")
        snapshot.network = try decode(ItemCollection<NetworkInterface>.self, "network")
        return snapshot
    }

    @Test func readsTheValuesOfTheWholeServer() throws {
        let snapshot = try snapshot()
        let cpu = try #require(MetricReader.read(RuleMetric(.cpu), from: snapshot).first)
        #expect(cpu.item == nil)
        #expect(cpu.value == snapshot.cpu?.value.total)
        #expect(MetricReader.read(RuleMetric(.memory), from: snapshot).first?.value == snapshot.memory?.value.percent)
        #expect(MetricReader.read(RuleMetric(.swap), from: snapshot).first?.value == snapshot.swap?.value.percent)
        #expect(MetricReader.read(RuleMetric(.load), from: snapshot).first?.value == snapshot.load?.value.min5)
        #expect((0...100).contains(try #require(MetricReader.read(RuleMetric(.memory), from: snapshot).first).value))
    }

    @Test func readsEveryFileSystemOrOne() throws {
        let snapshot = try snapshot()
        let all = MetricReader.read(RuleMetric(.disk), from: snapshot)
        #expect(all.count == snapshot.fileSystems?.items.count)
        #expect(all.first { $0.item == "/mnt/volume-01" }?.value == 20.4)
        #expect(all.first { $0.item == "/mnt/volume-02" }?.value == 5.7)

        let one = MetricReader.read(RuleMetric(.disk, item: "/mnt/volume-02"), from: snapshot)
        #expect(one == [MetricValue(item: "/mnt/volume-02", value: 5.7)])
        #expect(MetricReader.read(RuleMetric(.disk, item: "/nowhere"), from: snapshot).isEmpty)
    }

    @Test func readsTemperaturesOnly() throws {
        let snapshot = try snapshot()
        let all = MetricReader.read(RuleMetric(.temperature), from: snapshot)
        let labels = all.compactMap(\.item)
        #expect(labels.contains("Composite"))
        #expect(!labels.contains("pwmfan 0"))
        #expect(all.first { $0.item == "Composite" }?.value == 36)
        #expect(MetricReader.read(RuleMetric(.temperature, item: "Composite"), from: snapshot).count == 1)
    }

    @Test func addsUpTheInterfacesWithoutLoopbackInMegabytes() throws {
        var snapshot = try snapshot()
        snapshot.network = ItemCollection(items: [
            try interface("lo", recv: 5_000_000, sent: 5_000_000),
            try interface("eth0", recv: 2_000_000, sent: 500_000),
            try interface("wlan0", recv: 1_000_000, sent: 250_000),
            try interface("eth1", recv: 9_000_000, sent: 9_000_000, up: false),
        ])
        #expect(MetricReader.read(RuleMetric(.networkDown), from: snapshot) == [MetricValue(value: 3)])
        #expect(MetricReader.read(RuleMetric(.networkUp), from: snapshot) == [MetricValue(value: 0.75)])
    }

    @Test func realNetworkFixtureGivesAFiniteRate() throws {
        let value = try #require(MetricReader.read(RuleMetric(.networkDown), from: try snapshot()).first)
        #expect(value.value >= 0 && value.value.isFinite)
    }

    @Test func missingDataGivesNoValues() {
        let empty = ServerSnapshot()
        for kind in RuleMetric.Kind.allCases {
            #expect(MetricReader.read(RuleMetric(kind), from: empty).isEmpty, "\(kind)")
        }
    }

    @Test func nanIsNotAValue() throws {
        var snapshot = try snapshot()
        snapshot.cpu?.value.total = .nan
        #expect(MetricReader.read(RuleMetric(.cpu), from: snapshot).isEmpty)
    }

    private func interface(_ name: String, recv: Double, sent: Double, up: Bool = true) throws -> NetworkInterface {
        let json = #"{"interface_name":"\#(name)","bytes_recv":\#(recv),"bytes_sent":\#(sent),"is_up":\#(up)}"#
        return try JSONDecoder().decode(NetworkInterface.self, from: Data(json.utf8))
    }
}
