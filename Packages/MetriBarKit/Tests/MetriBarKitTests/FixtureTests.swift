import Foundation
import Testing

@testable import MetriBarKit

struct FixtureTests {
    @Test func allFixturesAreValidJSON() throws {
        let names = try Fixture.names()
        #expect(names.count >= 20)
        for name in names {
            let data = try Fixture.data(name)
            #expect(throws: Never.self, "\(name).json") {
                try JSONSerialization.jsonObject(with: data)
            }
        }
    }

    @Test func fixturesComeFromGlances5() throws {
        let status = try JSONSerialization.jsonObject(with: Fixture.data("status")) as? [String: Any]
        #expect(status?["version"] as? String == "5")
    }

    @Test func levelsInRealPayloadDecode() throws {
        struct Payload: Decodable {
            let levels: [String: LevelInfo]

            enum CodingKeys: String, CodingKey {
                case levels = "_levels"
            }
        }
        let cpu = try JSONDecoder().decode(Payload.self, from: Fixture.data("cpu"))
        #expect(cpu.levels["total"] != nil)
        #expect(cpu.levels.values.allSatisfy { $0.level != .unknown })
    }
}
