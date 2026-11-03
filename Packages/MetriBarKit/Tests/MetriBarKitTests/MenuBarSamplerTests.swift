import Foundation
import Testing

@testable import MetriBarKit

struct MenuBarSamplerTests {
    private let server = UUID()

    private func snapshot(cpu: Double? = nil, memory: Double? = nil) -> ServerSnapshot {
        var snapshot = ServerSnapshot()
        if let cpu {
            snapshot.cpu = Reading(value: try! JSONDecoder().decode(CPU.self, from: Data(#"{"total":\#(cpu)}"#.utf8)))
        }
        if let memory {
            snapshot.memory = Reading(
                value: try! JSONDecoder().decode(Memory.self, from: Data(#"{"percent":\#(memory)}"#.utf8)))
        }
        return snapshot
    }

    @Test func recordsEachItemInOrder() {
        var sampler = MenuBarSampler()
        sampler.record(serverID: server, items: [.cpu, .memory], snapshot: snapshot(cpu: 10, memory: 50))
        sampler.record(serverID: server, items: [.cpu, .memory], snapshot: snapshot(cpu: 20, memory: 55))
        #expect(sampler.history(for: .cpu) == [10, 20])
        #expect(sampler.history(for: .memory) == [50, 55])
        #expect(sampler.history(for: .load).isEmpty)
    }

    @Test func keepsOnlyTheLatestSamples() {
        var sampler = MenuBarSampler()
        for value in 0..<(SampleHistory.capacity + 10) {
            sampler.record(serverID: server, items: [.cpu], snapshot: snapshot(cpu: Double(value)))
        }
        let history = sampler.history(for: .cpu)
        #expect(history.count == SampleHistory.capacity)
        #expect(history.first == 10)
        #expect(history.last == Double(SampleHistory.capacity + 9))
    }

    @Test func anotherServerStartsANewHistory() {
        var sampler = MenuBarSampler()
        sampler.record(serverID: server, items: [.cpu], snapshot: snapshot(cpu: 10))
        sampler.record(serverID: UUID(), items: [.cpu], snapshot: snapshot(cpu: 90))
        #expect(sampler.history(for: .cpu) == [90])
    }

    @Test func removedItemsAreForgotten() {
        var sampler = MenuBarSampler()
        sampler.record(serverID: server, items: [.cpu, .memory], snapshot: snapshot(cpu: 10, memory: 50))
        sampler.record(serverID: server, items: [.cpu], snapshot: snapshot(cpu: 11, memory: 51))
        #expect(sampler.history(for: .memory).isEmpty)
        // Back again: a fresh start, not the old values.
        sampler.record(serverID: server, items: [.cpu, .memory], snapshot: snapshot(cpu: 12, memory: 52))
        #expect(sampler.history(for: .memory) == [52])
    }

    @Test func aServerThatCannotBeReadLeavesAGapNotAValue() {
        var sampler = MenuBarSampler()
        sampler.record(serverID: server, items: [.cpu], snapshot: snapshot(cpu: 10))
        sampler.record(serverID: server, items: [.cpu], snapshot: nil)
        sampler.record(serverID: server, items: [.cpu], snapshot: snapshot(cpu: 12))
        #expect(sampler.history(for: .cpu) == [10, 12])
    }

    @Test func aMissingValueIsNotRecorded() {
        var sampler = MenuBarSampler()
        sampler.record(serverID: server, items: [.cpu, .memory], snapshot: snapshot(cpu: 10))
        #expect(sampler.history(for: .cpu) == [10])
        #expect(sampler.history(for: .memory).isEmpty)
    }

    @Test func notAFiniteNumberIsIgnored() {
        var history = SampleHistory()
        history.append(.nan)
        history.append(.infinity)
        history.append(3)
        #expect(history.values == [3])
    }

    @Test func percentagesHaveAFixedRange() {
        #expect(MenuBarMetric.cpu.fixedRange == 0...100)
        #expect(MenuBarMetric.disk.fixedRange == 0...100)
        #expect(MenuBarMetric.networkDown.fixedRange == nil)
        #expect(MenuBarMetric.temperature.fixedRange == nil)
    }

    @Test func trendSettingIsOffByDefaultAndTolerant() throws {
        #expect(!Preferences().menuBarTrend)
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"menuBarItems":["cpu"]}"#.utf8))
        #expect(!old.menuBarTrend)
        let on = try JSONDecoder().decode(
            Preferences.self, from: Data(#"{"menuBarTrend":true,"menuBarVisibility":"sometimes"}"#.utf8))
        #expect(on.menuBarTrend)
        #expect(on.menuBarVisibility == .always)
    }
}
