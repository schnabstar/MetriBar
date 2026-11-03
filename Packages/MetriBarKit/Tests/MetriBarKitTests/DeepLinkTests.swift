import Foundation
import Testing

@testable import MetriBarKit

struct DeepLinkTests {
    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func roundTrips() {
        #expect(DeepLink(url: DeepLink.dashboard.url) == .dashboard)
        #expect(DeepLink(url: DeepLink.server(id).url) == .server(id))
        #expect(DeepLink.server(id).url.absoluteString == "metribar://server/11111111-2222-3333-4444-555555555555")
    }

    @Test func acceptsHarmlessVariants() {
        #expect(DeepLink(url: URL(string: "METRIBAR://Dashboard")!) == .dashboard)
        #expect(DeepLink(url: URL(string: "metribar://dashboard/")!) == .dashboard)
        #expect(DeepLink(url: URL(string: "metribar://dashboard?utm=x#top")!) == .dashboard)
        #expect(DeepLink(url: URL(string: "metribar://server/\(id.uuidString.lowercased())")!) == .server(id))
    }

    @Test(arguments: [
        "https://dashboard",
        "metribar:dashboard",
        "metribar://",
        "metribar://settings",
        "metribar://quit",
        "metribar://dashboard/extra",
        "metribar://server",
        "metribar://server/",
        "metribar://server/not-a-uuid",
        "metribar://server/11111111-2222-3333-4444-555555555555/alerts",
        "metribar://user@dashboard",
        "metribar://dashboard:80",
        "metribar://evil.example/dashboard",
        "other://dashboard",
    ])
    func rejectsEverythingElse(_ text: String) {
        #expect(URL(string: text).flatMap(DeepLink.init(url:)) == nil, "\(text)")
    }
}
