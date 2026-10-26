import Foundation

/// A built-in Glances 5 server with anonymized sample data, for SwiftUI
/// previews, screenshots and trying MetriBar without a server.
public enum DemoServer {
    public static let url = URL(string: "https://demo.metribar.invalid")!

    public static func config(name: String = "Demo") -> ServerConfig {
        ServerConfig(id: UUID(uuidString: "00000000-0000-0000-0000-00000000DE30")!, name: name, url: url)
    }

    public static func client() -> GlancesClient {
        GlancesClient(baseURL: url, transport: DemoTransport())
    }
}

struct DemoTransport: HTTPTransport {
    private static let routes: [String: String] = [
        "/status": "status",
        "/api/5/pluginslist": "pluginslist",
        "/api/5/system": "system",
        "/api/5/cpu": "cpu",
        "/api/5/percpu": "percpu",
        "/api/5/quicklook": "quicklook",
        "/api/5/mem": "mem",
        "/api/5/memswap": "memswap",
        "/api/5/load": "load",
        "/api/5/uptime": "uptime",
        "/api/5/processcount": "processcount",
        "/api/5/containers": "containers",
        "/api/5/fs": "fs",
        "/api/5/diskio": "diskio",
        "/api/5/network": "network",
        "/api/5/sensors": "sensors",
        "/api/5/alert": "alert",
        "/api/5/alert/incidents": "alert-incidents",
        "/api/5/cpu/history": "cpu-history",
        "/api/5/mem/history": "mem-history",
        "/api/5/load/history": "load-history",
        "/api/5/network/history": "network-history",
    ]

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? DemoServer.url
        var path = url.path()
        if path.hasPrefix("/api/5/processlist/top/") { path = "/api/5/processlist/top" }
        let name = path == "/api/5/processlist/top" ? "processlist-top" : Self.routes[path]

        guard let name, let file = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Demo")
        else {
            let body = Data(#"{"detail": "Not Found"}"#.utf8)
            return (body, HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!)
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (try Data(contentsOf: file), response)
    }
}
