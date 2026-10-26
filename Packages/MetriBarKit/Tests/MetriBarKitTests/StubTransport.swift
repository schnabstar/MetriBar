import Foundation
import Synchronization

@testable import MetriBarKit

/// Answers requests from a closure and records them.
final class StubTransport: HTTPTransport {
    struct Reply {
        var status: Int = 200
        var body: Data = Data()
        var headers: [String: String] = [:]

        static func json(_ string: String, status: Int = 200) -> Reply {
            Reply(status: status, body: Data(string.utf8), headers: ["Content-Type": "application/json"])
        }

        static func fixture(_ name: String) throws -> Reply {
            Reply(body: try Fixture.data(name), headers: ["Content-Type": "application/json"])
        }
    }

    private let handler: @Sendable (URLRequest) throws -> Reply
    private let recorded = Mutex<[URLRequest]>([])

    init(_ handler: @escaping @Sendable (URLRequest) throws -> Reply) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        recorded.withLock { $0 }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recorded.withLock { $0.append(request) }
        let reply = try handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (reply.body, response)
    }
}
