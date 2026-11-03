import Foundation

/// A semantic version such as `0.11.0` or `0.12.0-preview.1`.
///
/// Parses the tag of a GitHub release (with an optional leading `v`) and the
/// `CFBundleShortVersionString` of the app. A pre-release is older than the
/// release with the same number.
public struct AppVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Dot-separated identifiers after the hyphen, empty for a release.
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Returns `nil` unless `string` is `major.minor[.patch][-prerelease][+build]`.
    public init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        // Build metadata does not take part in the comparison.
        if let plus = text.firstIndex(of: "+") { text = text[..<plus] }

        var prerelease: [String] = []
        if let hyphen = text.firstIndex(of: "-") {
            prerelease = text[text.index(after: hyphen)...].split(separator: ".", omittingEmptySubsequences: false)
                .map(String.init)
            guard !prerelease.isEmpty, prerelease.allSatisfy(Self.isValidIdentifier) else { return nil }
            text = text[..<hyphen]
        }

        let numbers = text.split(separator: ".", omittingEmptySubsequences: false).map { part -> Int? in
            guard !part.isEmpty, part.allSatisfy(\.isASCIIDigit) else { return nil }
            return Int(part)
        }
        guard (2...3).contains(numbers.count), numbers.allSatisfy({ $0 != nil }) else { return nil }
        self.init(
            major: numbers[0] ?? 0, minor: numbers[1] ?? 0, patch: numbers.count > 2 ? numbers[2] ?? 0 : 0,
            prerelease: prerelease)
    }

    public var isPrerelease: Bool {
        !prerelease.isEmpty
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let left = [lhs.major, lhs.minor, lhs.patch]
        let right = [rhs.major, rhs.minor, rhs.patch]
        if left != right { return left.lexicographicallyPrecedes(right) }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, _): return false
        case (false, true): return true
        case (false, false): return comparePrerelease(lhs.prerelease, rhs.prerelease)
        }
    }

    /// SemVer rule 11: numeric identifiers compare as numbers and rank below
    /// alphanumeric ones; a longer list wins if all earlier ones are equal.
    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            switch (Int(left), Int(right)) {
            case (let a?, let b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left < right
            }
        }
        return lhs.count < rhs.count
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.allSatisfy { $0.isASCIIDigit || $0.isASCIILetter || $0 == "-" }
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }

    fileprivate var isASCIILetter: Bool {
        isASCII && isLetter
    }
}
