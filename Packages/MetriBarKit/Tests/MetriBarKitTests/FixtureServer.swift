import Foundation
import Synchronization
import Testing

@testable import MetriBarKit

/// A fake Glances 5 server that answers with the captured fixtures. Single
/// paths can be overridden while a test runs.
final class FixtureServer: Sendable {
    static let routes: [String: String] = [
        "/status": "status",
        "/api/5/pluginslist": "pluginslist",
        "/api/5/system": "system",
        "/api/5/cpu": "cpu",
        "/api/5/mem": "mem",
        "/api/5/load": "load",
        "/api/5/uptime": "uptime",
        "/api/5/quicklook": "quicklook",
        "/api/5/memswap": "memswap",
        "/api/5/processcount": "processcount",
        "/api/5/containers": "containers",
        "/api/5/fs": "fs",
        "/api/5/diskio": "diskio",
        "/api/5/network": "network",
        "/api/5/sensors": "sensors",
        "/api/5/processlist/top/50": "processlist-top",
        "/api/5/alert": "alert",
        "/api/5/alert/incidents": "alert-incidents",
        "/api/5/cpu/history": "cpu-history",
        "/api/5/mem/history": "mem-history",
        "/api/5/load/history": "load-history",
        "/api/5/network/history": "network-history",
    ]

    private final class State: Sendable {
        let overrides = Mutex<[String: StubTransport.Reply]>([:])
        let failure = Mutex<URLError.Code?>(nil)
    }

    private let state = State()
    let transport: StubTransport

    init() {
        let state = state
        transport = StubTransport { request in try Self.reply(for: request, state: state) }
    }

    func client() -> GlancesClient {
        GlancesClient(baseURL: URL(string: "https://glances.example.com")!, transport: transport)
    }

    /// Answers `path` with `reply` until `reset()`.
    func override(_ path: String, with reply: StubTransport.Reply) {
        state.overrides.withLock { $0[path] = reply }
    }

    /// Lets every request fail with `code`, as if the server were offline.
    func goOffline(_ code: URLError.Code = .cannotConnectToHost) {
        state.failure.withLock { $0 = code }
    }

    func reset() {
        state.overrides.withLock { $0 = [:] }
        state.failure.withLock { $0 = nil }
    }

    /// Paths requested so far, in order.
    var paths: [String] {
        transport.requests.compactMap { $0.url?.path }
    }

    func count(_ path: String) -> Int {
        paths.filter { $0 == path }.count
    }

    private static func reply(for request: URLRequest, state: State) throws -> StubTransport.Reply {
        if let code = state.failure.withLock({ $0 }) {
            throw URLError(code)
        }
        let path = request.url?.path ?? ""
        if let reply = state.overrides.withLock({ $0[path] }) {
            return reply
        }
        guard let fixture = Self.routes[path] else {
            return .json(#"{"detail": "Not Found"}"#, status: 404)
        }
        return try .fixture(fixture)
    }
}

/// Waits (in real time) until `condition` holds, for at most two seconds.
@MainActor
func waitUntil(
    _ message: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) async {
    for _ in 0..<2_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record(message ?? "Condition not met in time", sourceLocation: sourceLocation)
}
