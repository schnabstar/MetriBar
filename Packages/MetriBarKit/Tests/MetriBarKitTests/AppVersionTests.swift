import Testing

@testable import MetriBarKit

struct AppVersionTests {
    @Test func parsesReleaseTagsAndBundleVersions() {
        #expect(AppVersion("0.11.0") == AppVersion(major: 0, minor: 11, patch: 0))
        #expect(AppVersion("v0.11.0") == AppVersion(major: 0, minor: 11, patch: 0))
        #expect(AppVersion("V1.2.3") == AppVersion(major: 1, minor: 2, patch: 3))
        #expect(AppVersion(" 1.0 ") == AppVersion(major: 1, minor: 0, patch: 0))
    }

    @Test func parsesPrereleaseAndIgnoresBuildMetadata() {
        let preview = AppVersion("0.1.0-preview.1")
        #expect(preview == AppVersion(major: 0, minor: 1, patch: 0, prerelease: ["preview", "1"]))
        #expect(preview?.isPrerelease == true)
        #expect(AppVersion("1.0.0+abc") == AppVersion("1.0.0"))
        #expect(AppVersion("1.0.0-rc.1+abc")?.description == "1.0.0-rc.1")
    }

    @Test(arguments: ["", "v", "1", "1.2.3.4", "a.b.c", "1.2.x", "1..3", "-1.2.3", "1.2.3-", "1.2.3-a..b", "1.2.3-ä"])
    func rejectsGarbage(_ text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func comparesNumbersNumerically() {
        #expect(version("0.9.0") < version("0.11.0"))
        #expect(version("0.11.0") < version("0.11.1"))
        #expect(version("0.11.9") < version("1.0.0"))
        #expect(version("1.0") == version("1.0.0"))
    }

    @Test func prereleaseIsOlderThanTheRelease() {
        #expect(version("1.0.0-rc.1") < version("1.0.0"))
        #expect(version("1.0.0") > version("1.0.0-rc.1"))
        #expect(version("0.12.0-preview.1") > version("0.11.0"))
    }

    @Test func ordersPrereleasesLikeSemVer() {
        let ordered = [
            "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11",
            "1.0.0-rc.1", "1.0.0",
        ].map(version)
        for (older, newer) in zip(ordered, ordered.dropFirst()) {
            #expect(older < newer)
            #expect(!(newer < older))
        }
    }

    private func version(_ text: String) -> AppVersion {
        AppVersion(text)!
    }
}
