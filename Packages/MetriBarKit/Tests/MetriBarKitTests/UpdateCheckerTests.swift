import Foundation
import Testing

@testable import MetriBarKit

struct UpdateCheckerTests {
    private static func release(
        tag: String = "v0.12.0", prerelease: Bool = false, draft: Bool = false,
        url: String = "https://github.com/schnabstar/MetriBar/releases/tag/v0.12.0",
        assets: String =
            #"[{"name": "MetriBar-0.12.0.dmg", "browser_download_url": "https://github.com/schnabstar/MetriBar/releases/download/v0.12.0/MetriBar-0.12.0.dmg"}]"#
    ) -> StubTransport.Reply {
        .json(
            """
            {"tag_name": "\(tag)", "name": "MetriBar", "html_url": "\(url)", "draft": \(draft),
             "prerelease": \(prerelease), "assets": \(assets)}
            """)
    }

    private func result(current: String = "0.11.0", reply: StubTransport.Reply) async -> UpdateResult {
        let transport = StubTransport { _ in reply }
        return await UpdateChecker(currentVersion: AppVersion(current)!, transport: transport).check()
    }

    @Test func offersANewerRelease() async {
        guard case .available(let update) = await result(reply: Self.release()) else {
            Issue.record("expected an available update")
            return
        }
        #expect(update.appVersion == AppVersion("0.12.0"))
        #expect(update.pageURL.absoluteString == "https://github.com/schnabstar/MetriBar/releases/tag/v0.12.0")
        #expect(update.diskImageURL?.lastPathComponent == "MetriBar-0.12.0.dmg")
    }

    @Test func sameOrOlderReleaseIsUpToDate() async {
        #expect(await result(current: "0.12.0", reply: Self.release()) == .upToDate)
        #expect(await result(current: "0.13.0", reply: Self.release()) == .upToDate)
    }

    @Test func ignoresDraftsAndPrereleases() async {
        #expect(await result(reply: Self.release(prerelease: true)) == .upToDate)
        #expect(await result(reply: Self.release(draft: true)) == .upToDate)
    }

    @Test func aPreviewIsOfferedTheFinalRelease() async {
        guard case .available = await result(current: "0.12.0-preview.1", reply: Self.release()) else {
            Issue.record("expected an available update")
            return
        }
    }

    @Test func rejectsLinksOutsideTheRepository() async {
        for url in [
            "https://evil.example/schnabstar/MetriBar/releases/tag/v0.12.0",
            "http://github.com/schnabstar/MetriBar/releases/tag/v0.12.0",
            "https://github.com/someone-else/MetriBar/releases/tag/v0.12.0",
            "https://github.com.evil.example/schnabstar/MetriBar/releases",
            "https://user@github.com/schnabstar/MetriBar/releases",
            "https://github.com/schnabstar/MetriBar-fake/releases",
            "https://github.com/schnabstar/MetriBar/../../attacker/releases/tag/v0.12.0",
            "https://github.com/schnabstar/MetriBar/releases/../../../attacker/repo",
            "https://github.com/schnabstar/MetriBar/%2e%2e/%2E%2e/attacker/repo",
            "https://github.com/schnabstar/MetriBar/.%2e/attacker/repo",
            "https://github.com/schnabstar/MetriBar/releases/%2e/tag",
            "https://github.com/schnabstar/MetriBar/..%2F..%2Fattacker/repo",
            "https://github.com/schnabstar/MetriBar/releases%5C..%5Cattacker",
            "javascript:alert(1)",
        ] {
            #expect(await result(reply: Self.release(url: url)) == .failed(.invalidResponse), "\(url)")
        }
    }

    @Test func acceptsReleaseLinksWithEncodedCharacters() {
        #expect(
            ReleaseInfo.repositoryURL("https://github.com/schnabstar/MetriBar/releases/tag/v0.12.0-preview.1") != nil)
        #expect(
            ReleaseInfo.repositoryURL("https://github.com/schnabstar/MetriBar/releases/download/v1/My%20App.dmg") != nil
        )
        #expect(ReleaseInfo.repositoryURL("https://github.com/schnabstar/MetriBar/releases/tag/v1.0.0?x=..") != nil)
    }

    @Test func hostileAssetLinkIsDropped() async {
        for link in [
            "https://evil.example/MetriBar.dmg",
            "https://github.com/schnabstar/MetriBar/../../attacker/repo/releases/download/v1/MetriBar.dmg",
        ] {
            let assets = #"[{"name": "MetriBar.dmg", "browser_download_url": "\#(link)"}]"#
            guard case .available(let update) = await result(reply: Self.release(assets: assets)) else {
                Issue.record("expected an available update")
                return
            }
            #expect(update.diskImageURL == nil, "\(link)")
        }
    }

    @Test func garbageTagsAndBodiesAreInvalid() async {
        #expect(await result(reply: Self.release(tag: "nightly")) == .failed(.invalidResponse))
        #expect(await result(reply: .json("[]")) == .failed(.invalidResponse))
        #expect(await result(reply: .json("not json")) == .failed(.invalidResponse))
    }

    @Test func mapsErrorStatuses() async {
        #expect(await result(reply: .json("{}", status: 404)) == .failed(.notFound))
        #expect(await result(reply: .json("{}", status: 500)) == .failed(.invalidResponse))
    }

    @Test func readsTheRateLimitReset() async {
        let reset = Reply(status: 403, headers: ["X-RateLimit-Reset": "1800000000"])
        #expect(await result(reply: reset) == .failed(.rateLimited(until: Date(timeIntervalSince1970: 1_800_000_000))))

        let retry = Reply(status: 429, headers: ["Retry-After": "60"])
        let now = Date(timeIntervalSince1970: 1000)
        let transport = StubTransport { _ in retry }
        let checked = await UpdateChecker(currentVersion: AppVersion("0.11.0")!, transport: transport).check(now: now)
        #expect(checked == .failed(.rateLimited(until: Date(timeIntervalSince1970: 1060))))

        #expect(await result(reply: Reply(status: 403)) == .failed(.rateLimited(until: nil)))
    }

    @Test func transportFailureIsANetworkError() async {
        struct Offline: Error {}
        let transport = StubTransport { _ in throw Offline() }
        let checked = await UpdateChecker(currentVersion: AppVersion("0.11.0")!, transport: transport).check()
        #expect(checked == .failed(.network))
    }

    @Test func sendsOneAnonymousRequestToTheLatestRelease() async throws {
        let transport = StubTransport { _ in Self.release() }
        _ = await UpdateChecker(currentVersion: AppVersion("0.11.0")!, transport: transport).check()
        let request = try #require(transport.requests.first)
        #expect(transport.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url == UpdateChecker.latestReleaseURL)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MetriBar/0.11.0")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        // Nothing that identifies the user.
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.httpBody == nil)
    }

    private typealias Reply = StubTransport.Reply
}

struct AvailableUpdateTests {
    @Test func roundTripsThroughJSON() throws {
        let update = AvailableUpdate(
            version: "0.12.0", pageURL: URL(string: "https://github.com/schnabstar/MetriBar/releases/tag/v0.12.0")!,
            diskImageURL: nil)
        let decoded = try JSONDecoder().decode(AvailableUpdate.self, from: JSONEncoder().encode(update))
        #expect(decoded == update)
    }

    @Test func isOnlyCreatedFromAUsableRelease() {
        let page = "https://github.com/schnabstar/MetriBar/releases/tag/v1.0.0"
        #expect(AvailableUpdate(ReleaseInfo(tagName: "v1.0.0", htmlURL: page)) != nil)
        #expect(AvailableUpdate(ReleaseInfo(tagName: "nightly", htmlURL: page)) == nil)
        #expect(AvailableUpdate(ReleaseInfo(tagName: "v1.0.0", htmlURL: nil)) == nil)
        #expect(AvailableUpdate(ReleaseInfo(tagName: "v1.0.0", htmlURL: "https://evil.example/")) == nil)
    }
}

struct UpdatePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func isDueWithoutAPreviousCheck() {
        #expect(UpdatePolicy.isDue(lastCheck: nil, now: now))
    }

    @Test func waitsADay() {
        #expect(!UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        #expect(!UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-86_399), now: now))
        #expect(UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-86_400), now: now))
    }

    @Test func isDueWhenTheClockWasSetBack() {
        #expect(UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(60), now: now))
    }
}
