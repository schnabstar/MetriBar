import Foundation

/// The addresses the widgets open: `metribar://dashboard` and
/// `metribar://server/<id>`.
///
/// Any app or web page can open a `metribar:` address, so parsing is strict
/// and the only effect of a link is to bring up a window of MetriBar: no
/// link changes a setting, starts or stops anything, or reaches a server.
public enum DeepLink: Equatable, Sendable {
    case dashboard
    case server(UUID)

    public static let scheme = "metribar"

    public var url: URL {
        switch self {
        case .dashboard: URL(string: "\(Self.scheme)://dashboard")!
        case .server(let id): URL(string: "\(Self.scheme)://server/\(id.uuidString)")!
        }
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.user == nil, url.password == nil, url.port == nil,
            let host = url.host()?.lowercased()
        else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "dashboard" where path.isEmpty:
            self = .dashboard
        case "server" where path.count == 1:
            guard let id = UUID(uuidString: path[0]) else { return nil }
            self = .server(id)
        default:
            return nil
        }
    }
}
