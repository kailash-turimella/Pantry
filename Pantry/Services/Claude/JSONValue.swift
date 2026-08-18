import Foundation

/// A minimal any-JSON value. Used to hand hand-written JSON Schemas to the
/// Messages API's `output_config.format` without inventing a Codable type for
/// every schema shape.
indirect enum JSONValue: Encodable, Sendable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral,
                     ExpressibleByDictionaryLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .integer(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

/// Small builders so the schema literals below read like schemas rather than
/// nested dictionary soup.
enum Schema {
    static func object(
        properties: [String: JSONValue],
        required: [String],
        description: String? = nil
    ) -> JSONValue {
        var fields: [String: JSONValue] = [
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map { .string($0) }),
            "additionalProperties": false,
        ]
        if let description { fields["description"] = .string(description) }
        return .object(fields)
    }

    static func array(of items: JSONValue, description: String? = nil) -> JSONValue {
        var fields: [String: JSONValue] = ["type": "array", "items": items]
        if let description { fields["description"] = .string(description) }
        return .object(fields)
    }

    static func string(_ description: String, enumValues: [String]? = nil) -> JSONValue {
        var fields: [String: JSONValue] = ["type": "string", "description": .string(description)]
        if let enumValues { fields["enum"] = .array(enumValues.map { .string($0) }) }
        return .object(fields)
    }

    static func number(_ description: String) -> JSONValue {
        .object(["type": "number", "description": .string(description)])
    }

    static func integer(_ description: String) -> JSONValue {
        .object(["type": "integer", "description": .string(description)])
    }

    static func boolean(_ description: String) -> JSONValue {
        .object(["type": "boolean", "description": .string(description)])
    }

    /// `["string", "null"]` — structured outputs has no `minLength`/optionality
    /// beyond nullable types, so optional fields are modelled this way and kept
    /// in `required`.
    static func nullable(_ type: String, _ description: String) -> JSONValue {
        .object([
            "type": .array([.string(type), .string("null")]),
            "description": .string(description),
        ])
    }
}
