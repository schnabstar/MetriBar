import Foundation
import Testing

@testable import MetriBarKit

struct GlancesClientTests {
    private let base = URL(string: "https://glances.example.com")!

    private func client(
        base: URL? = nil, credentials: Credentials? = nil,
        _ handler: @escaping @Sendable (URLRequest) throws -> StubTransport.Reply
    ) -> (GlancesClient, StubTransport) {
        let transport = StubTransport(handler)
        return (GlancesClient(baseURL: base ?? self.base, credentials: credentials, transport: transport), transport)
    }

    private func expectError<T>(
        _ expected: GlancesError, sourceLocation: SourceLocation = #_sourceLocation,
        _ operation: () async throws(GlancesError) -> T
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected \(expected), got success", sourceLocation: sourceLocation)
        } catch {
            #expect(error == expected, sourceLocation: sourceLocation)
        }
    }

    // MARK: Requests

    @Test(arguments: [
        ("https://glances.example.com", "https://glances.example.com/api/5/cpu"),
        ("https://glances.example.com/", "https://glances.example.com/api/5/cpu"),
        ("https://proxy.example.com/glances/", "https://proxy.example.com/glances/api/5/cpu"),
        ("http://192.168.1.10:61208", "http://192.168.1.10:61208/api/5/cpu"),
    ])
    func buildsURLsRelativeToTheBaseURL(base: String, expected: String) async throws {
        let (client, transport) = client(base: URL(string: base)!) { _ in try .fixture("cpu") }
        _ = try await client.get(.cpu)
        #expect(transport.requests.first?.url?.absoluteString == expected)
    }

    @Test func sendsAcceptHeaderAndOnlyGET() async throws {
        let (client, transport) = client { _ in try .fixture("cpu") }
        _ = try await client.get(.cpu)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func sendsBasicAuthWhenCredentialsAreSet() async throws {
        let credentials = Credentials(username: "glances", password: "s3cret")
        let (client, transport) = client(credentials: credentials) { _ in try .fixture("cpu") }
        _ = try await client.get(.cpu)
        let header = transport.requests.first?.value(forHTTPHeaderField: "Authorization")
        #expect(header == "Basic " + Data("glances:s3cret".utf8).base64EncodedString())
    }

    @Test func historyQueryParameters() async throws {
        let (client, transport) = client { _ in try .fixture("network-history") }
        _ = try await client.get(.history("network", count: 60, item: "eth0"))
        let url = try #require(transport.requests.first?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/5/network/history")
        #expect(
            components.queryItems == [URLQueryItem(name: "nb", value: "60"), URLQueryItem(name: "item", value: "eth0")])
    }

    @Test func credentialsNeverPrintThePassword() {
        let credentials = Credentials(username: "glances", password: "s3cret")
        #expect(!"\(credentials)".contains("s3cret"))
        #expect(!String(reflecting: credentials).contains("s3cret"))
        var dumped = ""
        dump(credentials, to: &dumped)
        #expect(!dumped.contains("s3cret"))
    }

    // MARK: HTTP errors

    @Test func mapsUnauthorized() async {
        let (client, _) = client { _ in .json(#"{"detail": "Not authenticated"}"#, status: 401) }
        await expectError(.unauthorized) { () async throws(GlancesError) in try await client.get(.cpu) }
    }

    @Test func mapsNotFoundWithDetail() async {
        let (client, _) = client { _ in try .fixture("error-unknown-plugin").with(status: 404) }
        await expectError(.notFound(detail: "Plugin 'doesnotexist' not found")) { () async throws(GlancesError) in
            try await client.get(.gpu)
        }
    }

    @Test func mapsRateLimitWithRetryAfter() async {
        let (client, _) = client { _ in StubTransport.Reply(status: 429, headers: ["Retry-After": "30"]) }
        await expectError(.rateLimited(retryAfter: .seconds(30))) { () async throws(GlancesError) in
            try await client.get(.cpu)
        }
    }

    @Test func mapsBadRequestFromHostCheck() async {
        let (client, _) = client { _ in .json(#"{"detail": "Invalid host header"}"#, status: 400) }
        await expectError(.badRequest(detail: "Invalid host header")) { () async throws(GlancesError) in
            try await client.get(.cpu)
        }
    }

    @Test func mapsOtherStatusCodes() async {
        let (client, _) = client { _ in StubTransport.Reply(status: 502, body: Data("<html>Bad Gateway</html>".utf8)) }
        await expectError(.http(status: 502, detail: nil)) { () async throws(GlancesError) in try await client.get(.cpu)
        }
    }

    @Test func truncatesLongErrorDetails() async {
        let long = String(repeating: "x", count: 5_000)
        let (client, _) = client { _ in .json(#"{"detail": "\#(long)"}"#, status: 404) }
        await expectError(.notFound(detail: String(repeating: "x", count: 200))) { () async throws(GlancesError) in
            try await client.get(.cpu)
        }
    }

    // MARK: Transport errors

    @Test(arguments: [
        URLError.Code.cannotConnectToHost, .timedOut, .cannotFindHost, .serverCertificateUntrusted,
        .appTransportSecurityRequiresSecureConnection,
    ])
    func mapsURLErrors(code: URLError.Code) async {
        let (client, _) = client { _ in throw URLError(code) }
        await expectError(.transport(code)) { () async throws(GlancesError) in try await client.get(.cpu) }
    }

    @Test func mapsCancellation() async {
        let (client, _) = client { _ in throw URLError(.cancelled) }
        await expectError(.cancelled) { () async throws(GlancesError) in try await client.get(.cpu) }
    }

    @Test func mapsDecodingErrorsWithoutLeakingContent() async {
        let (client, _) = client { _ in .json(#"{"data": "not a list"}"#) }
        await expectError(.decoding("Unexpected type at top level, expected Array<Any>")) {
            () async throws(GlancesError) in
            try await client.get(.pluginsList)
        }
    }

    // MARK: Server detection

    @Test func acceptsGlances5() async throws {
        let (client, _) = client { _ in try .fixture("status") }
        let status = try await client.checkServer()
        #expect(status.version == "5")
    }

    @Test func detectsGlances4() async {
        let (client, transport) = client { request in
            request.url?.path == "/api/4/status"
                ? .json(#"{"version": "4.5.8"}"#) : .json(#"{"detail": "Not Found"}"#, status: 404)
        }
        await expectError(.unsupportedVersion("4")) { () async throws(GlancesError) in try await client.checkServer() }
        #expect(transport.requests.map(\.url?.path) == ["/status", "/api/4/status"])
    }

    @Test func rejectsFutureVersions() async {
        let (client, _) = client { _ in .json(#"{"status": "ok", "version": "6", "glances_version": "6.0.0"}"#) }
        await expectError(.unsupportedVersion("6.0.0")) { () async throws(GlancesError) in
            try await client.checkServer()
        }
    }

    @Test func rejectsOtherServers() async {
        let (htmlClient, _) = client { _ in StubTransport.Reply(body: Data("<html>Welcome to nginx</html>".utf8)) }
        await expectError(.notGlances) { () async throws(GlancesError) in try await htmlClient.checkServer() }

        let (jsonClient, _) = client { _ in .json(#"{"hello": "world"}"#) }
        await expectError(.notGlances) { () async throws(GlancesError) in try await jsonClient.checkServer() }

        let (missingClient, _) = client { _ in StubTransport.Reply(status: 404) }
        await expectError(.notGlances) { () async throws(GlancesError) in try await missingClient.checkServer() }
    }

    @Test func checkServerPassesThroughAuthAndTransportErrors() async {
        let (authClient, _) = client { _ in StubTransport.Reply(status: 401) }
        await expectError(.unauthorized) { () async throws(GlancesError) in try await authClient.checkServer() }

        let (offlineClient, _) = client { _ in throw URLError(.cannotConnectToHost) }
        await expectError(.transport(.cannotConnectToHost)) { () async throws(GlancesError) in
            try await offlineClient.checkServer()
        }
    }
}

extension StubTransport.Reply {
    fileprivate func with(status: Int) -> Self {
        var reply = self
        reply.status = status
        return reply
    }
}
