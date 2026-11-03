import Foundation

/// The parts of a GitHub release (`GET /repos/{owner}/{repo}/releases/latest`)
/// that the update check uses.
///
/// Links from the response are only exposed after checking that they point
/// into the MetriBar repository, so a manipulated answer cannot make the
/// app open another site.
public struct ReleaseInfo: Decodable, Sendable, Equatable {
    @Lenient public var tagName: String?
    @Lenient public var name: String?
    @Lenient public var htmlURL: String?
    @Lenient public var draft: Bool?
    @Lenient public var prerelease: Bool?
    @Lenient public var publishedAt: String?
    @Lenient public var assets: [Asset]?

    public struct Asset: Decodable, Sendable, Equatable {
        @Lenient public var name: String?
        @Lenient public var browserDownloadURL: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }

        public init(name: String?, browserDownloadURL: String?) {
            self.name = name
            self.browserDownloadURL = browserDownloadURL
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft, prerelease
        case publishedAt = "published_at"
        case assets
    }

    public init(
        tagName: String?, name: String? = nil, htmlURL: String?, draft: Bool? = false, prerelease: Bool? = false,
        publishedAt: String? = nil, assets: [Asset]? = nil
    ) {
        self.tagName = tagName
        self.name = name
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
        self.publishedAt = publishedAt
        self.assets = assets
    }

    /// The version this release announces, from its tag.
    public var version: AppVersion? {
        tagName.flatMap(AppVersion.init)
    }

    /// `true` for a regular, published release; a draft or pre-release is
    /// never offered.
    public var isRegularRelease: Bool {
        draft != true && prerelease != true
    }

    /// The release page, if it lies in the MetriBar repository.
    public var pageURL: URL? {
        htmlURL.flatMap(Self.repositoryURL)
    }

    /// The disk image of the release, if there is one in the repository.
    public var diskImageURL: URL? {
        assets?
            .first { $0.name?.hasSuffix(".dmg") == true }?
            .browserDownloadURL
            .flatMap(Self.repositoryURL)
    }

    /// Accepts `https://github.com/schnabstar/MetriBar/…` and nothing else.
    ///
    /// The path is checked segment by segment in its encoded form: a prefix
    /// check alone lets `…/MetriBar/../../other/` through, which opens
    /// another repository once the URL is resolved.
    static func repositoryURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
            url.scheme == "https",
            url.host()?.lowercased() == "github.com",
            url.user == nil, url.port == nil,
            url.path(percentEncoded: true).hasPrefix("/schnabstar/MetriBar/")
        else { return nil }
        let segments = url.path(percentEncoded: true).split(separator: "/", omittingEmptySubsequences: false)
            .dropFirst()
        for segment in segments {
            // Also catches `%2e%2e` and an encoded `/` or `\` inside a segment.
            guard let decoded = segment.removingPercentEncoding,
                decoded != ".", decoded != "..",
                !decoded.contains("/"), !decoded.contains("\\")
            else { return nil }
        }
        return url
    }
}

/// A newer release, reduced to what the app shows and stores: all links
/// have been checked to point into the MetriBar repository.
public struct AvailableUpdate: Codable, Sendable, Equatable {
    /// Normalized version number from the tag, for example `0.12.0`.
    public let version: String
    public let pageURL: URL
    public let diskImageURL: URL?

    public init(version: String, pageURL: URL, diskImageURL: URL?) {
        self.version = version
        self.pageURL = pageURL
        self.diskImageURL = diskImageURL
    }

    /// `nil` unless the release has a readable version and a valid page link.
    public init?(_ release: ReleaseInfo) {
        guard let version = release.version, let pageURL = release.pageURL else { return nil }
        self.init(version: version.description, pageURL: pageURL, diskImageURL: release.diskImageURL)
    }

    public var appVersion: AppVersion {
        AppVersion(version) ?? AppVersion(major: 0, minor: 0, patch: 0)
    }
}
