import Foundation

public enum ServerURLError: Error, Sendable, Equatable {
    case empty
    case unsupportedScheme(String)
    case missingHost
    /// User name or password inside the URL. They belong in the separate
    /// fields so the password ends up in the Keychain, not in the settings.
    case containsCredentials
    case invalid
}

public enum ServerURL {
    /// Turns user input into a server base URL.
    ///
    /// Adds `http://` when the scheme is missing (Glances serves plain HTTP
    /// on port 61208 by default), drops query and fragment, and removes a
    /// pasted API path such as `/api/5`. A path prefix of a reverse proxy,
    /// such as `/glances`, is kept.
    public static func parse(_ input: String) throws(ServerURLError) -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .empty }
        let withScheme = text.contains("://") ? text : "http://" + text
        guard var components = URLComponents(string: withScheme) else { throw .invalid }

        let scheme = components.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { throw .unsupportedScheme(scheme) }
        guard components.user == nil, components.password == nil else { throw .containsCredentials }
        guard let host = components.host, !host.isEmpty else { throw .missingHost }

        components.scheme = scheme
        components.host = host.lowercased()
        components.query = nil
        components.fragment = nil
        components.path = normalizedPath(components.path)

        guard let url = components.url else { throw .invalid }
        return url
    }

    private static func normalizedPath(_ path: String) -> String {
        var path = path
        while path.hasSuffix("/") { path.removeLast() }
        for apiPath in ["/api/5", "/api/4", "/status"] where path.hasSuffix(apiPath) {
            path.removeLast(apiPath.count)
        }
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
