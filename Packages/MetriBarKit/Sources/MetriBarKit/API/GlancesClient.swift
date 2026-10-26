import Foundation

/// HTTP Basic credentials for a Glances server.
public struct Credentials: Sendable, Equatable {
    public var username: String
    public var password: String

    public init(username: String = "glances", password: String) {
        self.username = username
        self.password = password
    }

    var authorizationHeader: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }
}

extension Credentials: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    // Keep the password out of logs, debugger output and string interpolation.
    public var description: String { "Credentials(username: \(username), password: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["username": username]) }
}

/// Reads a Glances 5 server. Only sends `GET` requests: MetriBar never
/// changes anything on the server.
public struct GlancesClient: Sendable {
    public let baseURL: URL
    private let credentials: Credentials?
    private let transport: any HTTPTransport

    public init(
        baseURL: URL, credentials: Credentials? = nil, transport: any HTTPTransport = URLSessionTransport.shared
    ) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.transport = transport
    }

    public func get<Response>(_ endpoint: Endpoint<Response>) async throws(GlancesError) -> Response {
        let (data, response) = try await send(request(path: endpoint.path, queryItems: endpoint.queryItems))
        try Self.validate(response, data: data)
        return try Self.decode(Response.self, from: data)
    }

    /// Confirms that the server runs Glances 5.
    /// - Throws: `.unsupportedVersion` for Glances 4, `.notGlances` if
    ///   something else answers, or the error of the request.
    public func checkServer() async throws(GlancesError) -> ServerStatus {
        do throws(GlancesError) {
            let status = try await get(.status)
            guard let version = status.version else { throw GlancesError.notGlances }
            guard version == "5" else { throw GlancesError.unsupportedVersion(status.glancesVersion ?? version) }
            return status
        } catch .notFound {
            // Glances 4 has no /status route but serves /api/4/status.
            if await statusCode(path: "api/4/status") == 200 {
                throw .unsupportedVersion("4")
            }
            throw .notGlances
        } catch .decoding {
            throw .notGlances
        }
    }

    // MARK: - Request handling

    private func request(path: String, queryItems: [URLQueryItem] = []) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !queryItems.isEmpty {
            url.append(queryItems: queryItems)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let credentials {
            request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws(GlancesError) -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError {
            throw error.code == .cancelled ? .cancelled : .transport(error.code)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .transport(.unknown)
        }
        guard let http = response as? HTTPURLResponse else { throw .notGlances }
        return (data, http)
    }

    private func statusCode(path: String) async -> Int? {
        try? await send(request(path: path)).1.statusCode
    }

    static func validate(_ response: HTTPURLResponse, data: Data) throws(GlancesError) {
        switch response.statusCode {
        case 200..<300:
            return
        case 400:
            throw .badRequest(detail: ErrorBody.detail(from: data))
        case 401:
            throw .unauthorized
        case 404:
            throw .notFound(detail: ErrorBody.detail(from: data))
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init).map(Duration.seconds)
            throw .rateLimited(retryAfter: retryAfter)
        default:
            throw .http(status: response.statusCode, detail: ErrorBody.detail(from: data))
        }
    }

    static func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws(GlancesError) -> Response {
        let decoder = JSONDecoder()
        // Python's json module writes NaN and Infinity, which JSON5 accepts.
        decoder.allowsJSON5 = true
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            throw .decoding(error.safeDescription)
        } catch {
            throw .decoding("Invalid response")
        }
    }
}
