import Foundation

/// Reads and writes the `WidgetSnapshot` file in a directory, which is the
/// App Group container in the app and in the widget extension.
public struct WidgetSnapshotStore: Sendable {
    public static let fileName = "widget-snapshot.json"

    private let url: URL

    public init(directory: URL) {
        url = directory.appending(path: Self.fileName)
    }

    /// Writes the file in one step, so a reader never sees half of it.
    public func write(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    /// The snapshot, or `nil` if there is none, it is unreadable or it comes
    /// from a later version of MetriBar that this reader does not understand.
    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
            snapshot.version <= WidgetSnapshot.currentVersion
        else { return nil }
        return snapshot
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// When the app writes a new snapshot and asks the widgets to reload.
///
/// Reloading costs the widgets' daily budget, so it happens at most every
/// five minutes, or at once (but not more than every 30 seconds) when a
/// server's state changed. The file itself is cheap and written every
/// minute if something changed.
public struct WidgetUpdatePolicy: Sendable {
    public static let writeInterval: TimeInterval = 60
    public static let reloadInterval: TimeInterval = 5 * 60
    public static let urgentReloadInterval: TimeInterval = 30

    public enum Action: Sendable, Equatable {
        case nothing
        case write
        case writeAndReload
    }

    public init() {}

    public func decide(
        previous: WidgetSnapshot?, next: WidgetSnapshot, lastWrite: Date?, lastReload: Date?, now: Date
    ) -> Action {
        let sinceReload = lastReload.map { now.timeIntervalSince($0) } ?? .infinity
        let sinceWrite = lastWrite.map { now.timeIntervalSince($0) } ?? .infinity

        guard let previous else { return .writeAndReload }
        if Self.healthChanged(previous, next) {
            return sinceReload >= Self.urgentReloadInterval ? .writeAndReload : .write
        }
        let changed = Self.valuesChanged(previous, next)
        if sinceReload >= Self.reloadInterval, changed || sinceWrite >= Self.reloadInterval {
            return .writeAndReload
        }
        if changed, sinceWrite >= Self.writeInterval { return .write }
        return .nothing
    }

    /// A server was added, removed, renamed or changed its state.
    static func healthChanged(_ a: WidgetSnapshot, _ b: WidgetSnapshot) -> Bool {
        a.servers.map { [$0.id.uuidString, $0.name, $0.health.rawValue] }
            != b.servers.map { [$0.id.uuidString, $0.name, $0.health.rawValue] }
    }

    /// A value moved by a point or more, or appeared or vanished.
    static func valuesChanged(_ a: WidgetSnapshot, _ b: WidgetSnapshot) -> Bool {
        for (old, new) in zip(a.servers, b.servers) {
            for (x, y) in [
                (old.cpu, new.cpu), (old.memory, new.memory), (old.disk, new.disk), (old.temperature, new.temperature),
            ] {
                switch (x, y) {
                case (nil, nil): continue
                case (let x?, let y?): if abs(x - y) >= 1 { return true }
                default: return true
                }
            }
        }
        return false
    }
}
