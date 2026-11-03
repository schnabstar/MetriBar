import Foundation
import Testing

@testable import MetriBarKit

struct MenuBarTextTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

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
        snapshot.containers = try decode(ItemCollection<ContainerInfo>.self, "containers")
        return snapshot
    }

    // MARK: - Reading

    @Test func everyMetricHasAValueInARealSnapshot() throws {
        let snapshot = try snapshot()
        for metric in MenuBarMetric.allCases {
            #expect(MenuBarText.value(metric, from: snapshot) != nil, "\(metric)")
        }
        #expect(MenuBarText.value(.cpu, from: snapshot) == snapshot.cpu?.value.total)
        #expect(MenuBarText.value(.memory, from: snapshot) == snapshot.memory?.value.percent)
        #expect(MenuBarText.value(.load, from: snapshot) == snapshot.load?.value.min5)
    }

    @Test func missingDataGivesNoSegments() {
        let empty = ServerSnapshot()
        for metric in MenuBarMetric.allCases {
            #expect(MenuBarText.value(metric, from: empty) == nil, "\(metric)")
        }
        #expect(MenuBarText.segments(MenuBarMetric.allCases, from: empty).isEmpty)
    }

    @Test func diskIsTheFullestFileSystemAndTemperatureTheHottestSensor() throws {
        var snapshot = try snapshot()
        let fileSystems = try ["/a": 20.0, "/b": 91.5, "/c": 40.0].sorted { $0.key < $1.key }.map { mount, percent in
            try JSONDecoder().decode(
                FileSystem.self, from: Data(#"{"mnt_point":"\#(mount)","percent":\#(percent)}"#.utf8))
        }
        snapshot.fileSystems = ItemCollection(items: fileSystems)
        #expect(MenuBarText.value(.disk, from: snapshot) == 91.5)
        // The fixture has 36, 52 and 40 degrees; the fan is not a temperature.
        #expect(MenuBarText.value(.temperature, from: try self.snapshot()) == 52)
    }

    @Test func containersCountTheUnhealthyOnes() throws {
        var snapshot = try snapshot()
        #expect(MenuBarText.value(.containers, from: snapshot) == 0)
        var items = try #require(snapshot.containers?.items)
        items[0].status = "unhealthy"
        items[1].status = "UNHEALTHY"
        items[2].status = "exited"
        snapshot.containers?.items = items
        #expect(MenuBarText.value(.containers, from: snapshot) == 2)
    }

    @Test func networkIsInBytesPerSecondOfAllInterfacesWithoutLoopback() throws {
        var snapshot = try snapshot()
        snapshot.network = ItemCollection(items: [
            try interface("lo", recv: 9_000_000, sent: 9_000_000),
            try interface("eth0", recv: 1_500_000, sent: 20_000),
        ])
        let segments = MenuBarText.segments([.networkDown, .networkUp], from: snapshot, locale: english)
        #expect(segments.map(\.text) == ["1.5 MB/s", "20 KB/s"])
    }

    // MARK: - Segments

    @Test func segmentsKeepTheOrderAndDropDuplicatesAndTheExcess() throws {
        let snapshot = try snapshot()
        let segments = MenuBarText.segments([.memory, .cpu, .memory, .load, .swap], from: snapshot, locale: english)
        #expect(segments.map(\.metric) == [.memory, .cpu, .load])
    }

    @Test func aValueTheServerDidNotReportIsLeftOut() throws {
        var snapshot = try snapshot()
        snapshot.sensors = nil
        let segments = MenuBarText.segments([.cpu, .temperature, .memory], from: snapshot, locale: english)
        #expect(segments.map(\.metric) == [.cpu, .memory])
    }

    // MARK: - Formatting

    @Test func formatsPercentLoadAndTemperature() {
        #expect(MenuBarText.format(42.4, .cpu, locale: english) == "42%")
        #expect(MenuBarText.format(42.6, .memory, locale: english) == "43%")
        #expect(MenuBarText.format(0.94, .load, locale: english) == "0.94")
        #expect(MenuBarText.format(52.4, .temperature, locale: english) == "52 °C")
        #expect(MenuBarText.format(3, .containers, locale: english) == "3")
    }

    @Test func formatsWithTheLocale() {
        #expect(MenuBarText.format(0.94, .load, locale: german) == "0,94")
        #expect(MenuBarText.rate(1_500_000, locale: german) == "1,5 MB/s")
        let percent = MenuBarText.format(42, .cpu, locale: german)
        #expect(percent.hasPrefix("42") && percent.hasSuffix("%"))
    }

    @Test func ratesUseTheUnitThatKeepsTheNumberShort() {
        #expect(MenuBarText.rate(0, locale: english) == "0 B/s")
        #expect(MenuBarText.rate(999, locale: english) == "999 B/s")
        #expect(MenuBarText.rate(1_000, locale: english) == "1 KB/s")
        #expect(MenuBarText.rate(1_260, locale: english) == "1.3 KB/s")
        #expect(MenuBarText.rate(12_600, locale: english) == "13 KB/s")
        #expect(MenuBarText.rate(999_000, locale: english) == "999 KB/s")
        #expect(MenuBarText.rate(2_000_000_000, locale: english) == "2 GB/s")
        // The largest unit is GB/s, whatever the number.
        #expect(MenuBarText.rate(5_000_000_000_000, locale: english) == "5,000 GB/s")
        #expect(MenuBarText.rate(-5, locale: english) == "0 B/s")
    }

    @Test func feedsOfTheMetrics() {
        #expect(MenuBarMetric.requiredFeeds([.cpu, .memory, .load, .containers, .temperature]).isEmpty)
        #expect(MenuBarMetric.requiredFeeds([.disk, .networkDown, .swap]) == [.storage, .network])
    }

    private func interface(_ name: String, recv: Double, sent: Double) throws -> NetworkInterface {
        let json = #"{"interface_name":"\#(name)","bytes_recv":\#(recv),"bytes_sent":\#(sent),"is_up":true}"#
        return try JSONDecoder().decode(NetworkInterface.self, from: Data(json.utf8))
    }
}
