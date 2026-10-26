import Foundation
import Testing

@testable import MetriBarKit

struct LenientDecodingTests {
    private struct Sample: Decodable, Equatable {
        @Lenient var number: Double?
        @Lenient var text: String?
        @Lenient var list: StringList?
    }

    private func decode<T: Decodable>(_ json: String, as type: T.Type = Sample.self) throws -> T {
        try GlancesClient.decode(type, from: Data(json.utf8))
    }

    @Test func missingKeysBecomeNil() throws {
        #expect(try decode("{}") == Sample(number: nil, text: nil, list: nil))
    }

    @Test func nullBecomesNil() throws {
        #expect(try decode(#"{"number": null, "text": null}"#).number == nil)
    }

    @Test func wrongTypeBecomesNilWithoutFailingOtherFields() throws {
        let sample = try decode(#"{"number": "fast", "text": "ok"}"#)
        #expect(sample.number == nil)
        #expect(sample.text == "ok")
    }

    @Test func stringListAcceptsStringAndArray() throws {
        #expect(try decode(#"{"list": "nginx:latest"}"#).list == StringList(["nginx:latest"]))
        #expect(try decode(#"{"list": ["a:1", "b:2"]}"#).list == StringList(["a:1", "b:2"]))
    }

    @Test func pythonNaNIsAccepted() throws {
        let sample = try decode(#"{"number": NaN, "text": "ok"}"#)
        #expect(sample.number?.isNaN == true)
        #expect(sample.text == "ok")
    }

    @Test func collectionSkipsItemsThatAreNotObjects() throws {
        let json = #"{"_key": "name", "data": [{"name": "a"}, 42, "junk", {"name": "b"}]}"#
        let collection = try decode(json, as: ItemCollection<ContainerInfo>.self)
        #expect(collection.items.map(\.name) == ["a", "b"])
        #expect(collection.key == "name")
    }

    @Test func collectionWithoutDataIsEmpty() throws {
        let collection = try decode(#"{"_levels": {}}"#, as: ItemCollection<ContainerInfo>.self)
        #expect(collection.items.isEmpty)
    }

    @Test func malformedLevelsDoNotFailThePayload() throws {
        let reading = try decode(#"{"total": 12.5, "_levels": "broken"}"#, as: Reading<CPU>.self)
        #expect(reading.value.total == 12.5)
        #expect(reading.levels.isEmpty)
        #expect(reading.level("total") == .unknown)
    }

    @Test func invalidJSONReportsPathWithoutContent() throws {
        #expect(throws: GlancesError.self) {
            try GlancesClient.decode([String].self, from: Data(#"{"secret": "value"}"#.utf8))
        }
        do {
            _ = try GlancesClient.decode([String].self, from: Data(#"{"secret": "value"}"#.utf8))
        } catch {
            guard case .decoding(let message) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(!message.contains("value"))
        }
    }

    @Test func parsesPythonISODates() {
        #expect(GlancesDate.parse("2026-10-26T07:37:11.435495+00:00") != nil)
        #expect(GlancesDate.parse("2026-10-26T07:37:11+00:00") != nil)
        #expect(GlancesDate.parse("yesterday") == nil)
    }
}
