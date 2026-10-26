import Foundation
import Testing

@testable import MetriBarKit

struct LevelTests {
    @Test func decodesKnownLevels() throws {
        let json = Data(#"["ok", "careful", "warning", "critical"]"#.utf8)
        let levels = try JSONDecoder().decode([Level].self, from: json)
        #expect(levels == [.ok, .careful, .warning, .critical])
    }

    @Test func unknownLevelDecodesAsUnknown() throws {
        let json = Data(#"["alarm"]"#.utf8)
        let levels = try JSONDecoder().decode([Level].self, from: json)
        #expect(levels == [.unknown])
    }

    @Test func levelsAreOrderedBySeverity() {
        #expect(Level.unknown < .ok)
        #expect(Level.ok < .careful)
        #expect(Level.careful < .warning)
        #expect(Level.warning < .critical)
        #expect([Level.careful, .critical, .ok].max() == .critical)
    }

    @Test func decodesLevelsObject() throws {
        let json = Data(
            #"""
            {
                "total": {"level": "ok", "prominent": true},
                "iowait": {"level": "warning", "prominent": false}
            }
            """#.utf8)
        let levels = try JSONDecoder().decode([String: LevelInfo].self, from: json)
        #expect(levels["total"] == LevelInfo(level: .ok, prominent: true))
        #expect(levels["iowait"] == LevelInfo(level: .warning, prominent: false))
    }

    @Test func missingFieldsFallBackToDefaults() throws {
        let json = Data(#"{}"#.utf8)
        let info = try JSONDecoder().decode(LevelInfo.self, from: json)
        #expect(info == LevelInfo(level: .unknown, prominent: false))
    }
}
