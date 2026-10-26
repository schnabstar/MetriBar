/// Decodes a field leniently: a missing key, `null` or a value of an
/// unexpected type become `nil` instead of failing the whole payload.
/// Glances 5 is still in beta, so field types may change between builds.
@propertyWrapper
public struct Lenient<Value: Decodable & Sendable>: Decodable, Sendable {
    public var wrappedValue: Value?

    public init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        wrappedValue = try? decoder.singleValueContainer().decode(Value.self)
    }
}

extension Lenient: Equatable where Value: Equatable {}

extension KeyedDecodingContainer {
    // Called by synthesized `init(from:)` for `@Lenient` properties, so that a
    // missing key does not throw `keyNotFound`.
    func decode<Value>(_ type: Lenient<Value>.Type, forKey key: Key) throws -> Lenient<Value> {
        (try? decodeIfPresent(type, forKey: key)) ?? Lenient(wrappedValue: nil)
    }
}

/// A value Glances sends either as a single string or as a list of strings,
/// for example a container's `image`, which the documentation describes as
/// a string but Glances 5.0.0b1 sends as a list of tags.
public struct StringList: Decodable, Sendable, Equatable {
    public var values: [String]

    public init(_ values: [String]) {
        self.values = values
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = [single]
        } else {
            values = try container.decode([String].self)
        }
    }
}

/// Decodes an array and drops the elements that fail to decode instead of
/// failing the whole array.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try container.decode(Skip.self)
            }
        }
        self.elements = elements
    }

    /// Consumes one element of any type.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}
