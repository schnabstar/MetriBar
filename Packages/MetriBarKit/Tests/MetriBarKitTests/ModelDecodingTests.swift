import Foundation
import Testing

@testable import MetriBarKit

/// Decodes the fixtures captured from a real Glances 5 server. The checks are
/// structural so that re-capturing the fixtures does not break them.
struct ModelDecodingTests {
    private func decode<Response>(_ endpoint: Endpoint<Response>, fixture: String) throws -> Response {
        try GlancesClient.decode(Response.self, from: Fixture.data(fixture))
    }

    private let percent = 0.0...100.0

    @Test func status() throws {
        let status = try decode(.status, fixture: "status")
        #expect(status.version == "5")
        #expect(status.glancesVersion?.hasPrefix("5.") == true)
    }

    @Test func pluginsList() throws {
        let plugins = try decode(.pluginsList, fixture: "pluginslist")
        #expect(plugins.contains("cpu"))
        #expect(plugins.contains("containers"))
    }

    @Test func system() throws {
        let system = try decode(.system, fixture: "system").value
        #expect(system.hostname == "glances-host")
        #expect(system.osName != nil)
        #expect(system.hrName != nil)
    }

    @Test func cpu() throws {
        let reading = try decode(.cpu, fixture: "cpu")
        #expect(reading.value.total.map(percent.contains) == true)
        #expect(reading.value.cpucore ?? 0 > 0)
        #expect(reading.level("total") != .unknown)
    }

    @Test func perCPU() throws {
        let cores = try decode(.perCPU, fixture: "percpu")
        #expect(!cores.items.isEmpty)
        #expect(cores.items.allSatisfy { $0.cpuNumber != nil && $0.total != nil })
    }

    @Test func quickLook() throws {
        let quickLook = try decode(.quickLook, fixture: "quicklook").value
        #expect(quickLook.cpu.map(percent.contains) == true)
        #expect(quickLook.percpu?.isEmpty == false)
        #expect(quickLook.percpu?.allSatisfy { $0.level != nil } == true)
    }

    @Test func memoryAndSwap() throws {
        let memory = try decode(.memory, fixture: "mem").value
        #expect(memory.percent.map(percent.contains) == true)
        #expect(memory.total ?? 0 > memory.used ?? .infinity)
        let swap = try decode(.swap, fixture: "memswap").value
        #expect(swap.total != nil)
    }

    @Test func loadAndUptime() throws {
        let load = try decode(.load, fixture: "load").value
        #expect(load.min1 != nil && load.min5 != nil && load.min15 != nil)
        #expect(load.cpucore ?? 0 > 0)
        let uptime = try decode(.uptime, fixture: "uptime").value
        #expect(uptime.duration ?? .zero > .zero)
    }

    @Test func processCount() throws {
        let count = try decode(.processCount, fixture: "processcount").value
        #expect(count.total ?? 0 > 0)
    }

    @Test func containers() throws {
        let containers = try decode(.containers, fixture: "containers")
        #expect(containers.key == "name")
        #expect(!containers.items.isEmpty)
        for container in containers.items {
            #expect(container.name != nil)
            #expect(container.imageName != nil)
            #expect(container.status != nil)
        }
        // On the capture server every container is up, most with a health check.
        #expect(containers.items.allSatisfy { $0.isRunning })
        #expect(containers.items.contains { $0.status == "healthy" })
        #expect(containers.items.contains { $0.startDate != nil })
    }

    @Test func storage() throws {
        let fileSystems = try decode(.fileSystems, fixture: "fs")
        #expect(fileSystems.key == "mnt_point")
        #expect(fileSystems.items.allSatisfy { $0.mntPoint != nil && $0.percent.map(percent.contains) == true })
        let disks = try decode(.diskIO, fixture: "diskio")
        #expect(disks.items.allSatisfy { $0.diskName != nil && $0.readBytes != nil })
    }

    @Test func network() throws {
        let interfaces = try decode(.network, fixture: "network")
        #expect(interfaces.key == "interface_name")
        #expect(interfaces.items.contains { $0.isUp == true && $0.bytesRecv != nil })
    }

    @Test func sensors() throws {
        let sensors = try decode(.sensors, fixture: "sensors")
        #expect(!sensors.items.isEmpty)
        #expect(sensors.items.contains { $0.kind == .temperature })
        #expect(sensors.items.allSatisfy { $0.value != nil && $0.unit != nil })
    }

    @Test func temperatureLevelFollowsHardwareThresholds() throws {
        func sensor(_ json: String) throws -> Sensor {
            try JSONDecoder().decode(Sensor.self, from: Data(json.utf8))
        }
        let base = #""type":"temperature_core","unit":"C""#
        #expect(try sensor("{\(base),\"value\":50,\"warning\":80,\"critical\":95}").level == .ok)
        #expect(try sensor("{\(base),\"value\":85,\"warning\":80,\"critical\":95}").level == .warning)
        #expect(try sensor("{\(base),\"value\":96,\"warning\":80,\"critical\":95}").level == .critical)
        #expect(try sensor("{\(base),\"value\":96,\"warning\":0,\"critical\":0}").level == .ok)
        #expect(try sensor(#"{"type":"fan_speed","value":9000,"warning":10,"critical":20}"#).level == .unknown)
    }

    @Test func processes() throws {
        let processes = try decode(.topProcesses(25), fixture: "processlist-top")
        #expect(!processes.isEmpty)
        #expect(processes.allSatisfy { $0.pid != nil && $0.name != nil })
        #expect(processes.contains { $0.memoryInfo?.rss != nil })
    }

    @Test func alertsAndIncidents() throws {
        let alerts = try decode(.alerts, fixture: "alert")
        #expect(alerts.isEmpty)  // nothing was alerting during the capture
        let incidents = try decode(.incidents, fixture: "alert-incidents")
        #expect(incidents.incidents != nil)
        #expect(incidents.isInitializing != nil)
    }

    @Test func syntheticAlertEvent() throws {
        // Shape from glances/alerts.py (_build_event); no real sample yet.
        let json = #"""
            [{"ts": "2026-10-26T07:37:11.435495+00:00", "plugin": "fs", "key": "/mnt/data",
              "field": "percent", "level": "warning", "previous_level": "careful", "value": 91.2,
              "prominent": false, "is_initial": false, "hostname": "glances-host"}]
            """#
        let event = try #require(try GlancesClient.decode([AlertEvent].self, from: Data(json.utf8)).first)
        #expect(event.level == .warning)
        #expect(event.previousLevel == .careful)
        #expect(event.key == "/mnt/data")
        #expect(event.date != nil)
    }

    @Test func history() throws {
        let cpu = try decode(.history("cpu", count: 30), fixture: "cpu-history")
        #expect(cpu.timestamps.count == 30)
        #expect(cpu.points("user").count == 30)
        #expect(cpu.points("missing").isEmpty)
        let memory = try decode(.history("mem", count: 30, field: "percent"), fixture: "mem-history")
        #expect(Set(memory.series.keys) == ["percent"])
        let load = try decode(.history("load", count: 30), fixture: "load-history")
        #expect(Set(load.series.keys) == ["min1", "min5", "min15"])
        // Collection plugins nest the values per item.
        let network = try decode(.history("network", count: 30), fixture: "network-history")
        #expect(network.series.isEmpty)
        #expect(network.items(for: "bytes_recv").contains("eth0"))
        #expect(network.points("bytes_recv", item: "eth0").count == 30)
        #expect(network.points("bytes_recv").isEmpty)
    }

    @Test func historyAcceptsBothSeriesShapes() throws {
        let json = #"{"timestamps": [1, 2], "series": {"user": [1.5, null], "bytes_recv": {"eth0": [10, 20]}}}"#
        let history = try GlancesClient.decode(History.self, from: Data(json.utf8))
        #expect(history.points("user").map(\.value) == [1.5])
        #expect(history.points("bytes_recv", item: "eth0").map(\.value) == [10, 20])
    }

    @Test func historySkipsGaps() {
        let history = History(timestamps: [1, 2, 3], series: ["v": [1, nil, 3, 4]])
        #expect(history.points("v").map(\.value) == [1, 3])
    }

    @Test func limits() throws {
        let limits = try decode(.limits("cpu"), fixture: "cpu-limits")
        let total = try #require(limits["total"])
        #expect(total.careful ?? 0 < total.warning ?? 0)
        #expect(total.warning ?? 0 < total.critical ?? 0)
    }
}
