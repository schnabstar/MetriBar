import Foundation

/// A Glances 5 API route and the type of its response.
/// Paths are relative to the server's base URL.
public struct Endpoint<Response: Decodable & Sendable>: Sendable, Equatable {
    public var path: String
    public var queryItems: [URLQueryItem]

    public init(path: String, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.queryItems = queryItems
    }
}

extension Endpoint where Response == ServerStatus {
    public static var status: Self { Self(path: "status") }
}

extension Endpoint where Response == [String] {
    public static var pluginsList: Self { Self(path: "api/5/pluginslist") }
}

extension Endpoint where Response == Reading<SystemInfo> {
    public static var system: Self { Self(path: "api/5/system") }
}

extension Endpoint where Response == Reading<CPU> {
    public static var cpu: Self { Self(path: "api/5/cpu") }
}

extension Endpoint where Response == ItemCollection<CoreUsage> {
    public static var perCPU: Self { Self(path: "api/5/percpu") }
}

extension Endpoint where Response == Reading<QuickLook> {
    public static var quickLook: Self { Self(path: "api/5/quicklook") }
}

extension Endpoint where Response == Reading<Memory> {
    public static var memory: Self { Self(path: "api/5/mem") }
}

extension Endpoint where Response == Reading<Swap> {
    public static var swap: Self { Self(path: "api/5/memswap") }
}

extension Endpoint where Response == Reading<Load> {
    public static var load: Self { Self(path: "api/5/load") }
}

extension Endpoint where Response == Reading<Uptime> {
    public static var uptime: Self { Self(path: "api/5/uptime") }
}

extension Endpoint where Response == Reading<ProcessCount> {
    public static var processCount: Self { Self(path: "api/5/processcount") }
}

extension Endpoint where Response == ItemCollection<ContainerInfo> {
    public static var containers: Self { Self(path: "api/5/containers") }
}

extension Endpoint where Response == ItemCollection<FileSystem> {
    public static var fileSystems: Self { Self(path: "api/5/fs") }
}

extension Endpoint where Response == ItemCollection<DiskIO> {
    public static var diskIO: Self { Self(path: "api/5/diskio") }
}

extension Endpoint where Response == ItemCollection<NetworkInterface> {
    public static var network: Self { Self(path: "api/5/network") }
}

extension Endpoint where Response == ItemCollection<Sensor> {
    public static var sensors: Self { Self(path: "api/5/sensors") }
}

extension Endpoint where Response == ItemCollection<GPU> {
    public static var gpu: Self { Self(path: "api/5/gpu") }
}

extension Endpoint where Response == [ProcessEntry] {
    /// The first `count` processes in the server's sort order.
    public static func topProcesses(_ count: Int) -> Self {
        Self(path: "api/5/processlist/top/\(max(1, count))")
    }
}

extension Endpoint where Response == [AlertEvent] {
    public static var alerts: Self { Self(path: "api/5/alert") }
}

extension Endpoint where Response == AlertIncidents {
    public static var incidents: Self { Self(path: "api/5/alert/incidents") }
}

extension Endpoint where Response == [String: Thresholds] {
    public static func limits(_ plugin: String) -> Self {
        Self(path: "api/5/\(plugin)/limits")
    }
}

extension Endpoint where Response == History {
    /// - Parameters:
    ///   - count: Number of points, 0 for all points Glances keeps.
    ///   - field: Only this field, otherwise Glances picks its defaults.
    ///   - item: Item key for collection plugins, such as an interface name.
    public static func history(_ plugin: String, count: Int = 0, field: String? = nil, item: String? = nil) -> Self {
        var query = [URLQueryItem(name: "nb", value: String(max(0, count)))]
        if let field { query.append(URLQueryItem(name: "field", value: field)) }
        if let item { query.append(URLQueryItem(name: "item", value: item)) }
        return Self(path: "api/5/\(plugin)/history", queryItems: query)
    }
}
