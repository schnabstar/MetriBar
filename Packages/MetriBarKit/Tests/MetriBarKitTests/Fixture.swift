import Foundation

/// Anonymized responses captured from a real Glances 5 server with
/// `Scripts/capture-fixtures.py`. See `Fixtures/v5/META.json`.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/v5") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func names() throws -> [String] {
        guard let directory = Bundle.module.url(forResource: "v5", withExtension: nil, subdirectory: "Fixtures") else {
            throw FixtureError.missing("v5")
        }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }
}

enum FixtureError: Error {
    case missing(String)
}
