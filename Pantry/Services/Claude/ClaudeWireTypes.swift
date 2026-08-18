import Foundation

// MARK: - Request

/// Body of `POST /v1/messages`. Field names map 1:1 to the wire format.
struct MessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [RequestMessage]
    let outputConfig: OutputConfig?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case outputConfig = "output_config"
    }
}

struct RequestMessage: Encodable {
    let role: String
    let content: [ContentBlock]

    static func user(_ blocks: [ContentBlock]) -> RequestMessage {
        RequestMessage(role: "user", content: blocks)
    }

    static func user(_ text: String) -> RequestMessage {
        RequestMessage(role: "user", content: [.text(text)])
    }
}

enum ContentBlock: Encodable {
    case text(String)
    case image(base64: String, mediaType: String)

    private enum CodingKeys: String, CodingKey { case type, text, source }
    private enum SourceKeys: String, CodingKey {
        case type, mediaType = "media_type", data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .image(let base64, let mediaType):
            try container.encode("image", forKey: .type)
            var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode(mediaType, forKey: .mediaType)
            try source.encode(base64, forKey: .data)
        }
    }
}

/// `output_config` carries both the effort dial and the structured-output schema.
struct OutputConfig: Encodable {
    let effort: String?
    let format: OutputFormat?

    struct OutputFormat: Encodable {
        let schema: JSONValue

        private enum CodingKeys: String, CodingKey { case type, schema }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("json_schema", forKey: .type)
            try container.encode(schema, forKey: .schema)
        }
    }
}

/// Effort levels supported by Claude Opus 5. Lower means fewer thinking tokens
/// and faster turnarounds; the extraction calls in this app don't need much.
enum Effort: String {
    case low, medium, high, xhigh, max
}

// MARK: - Response

struct MessagesResponse: Decodable {
    let id: String
    let model: String
    let stopReason: String?
    let stopDetails: StopDetails?
    let content: [ResponseBlock]
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case id, model, content, usage
        case stopReason = "stop_reason"
        case stopDetails = "stop_details"
    }

    /// First text block. Thinking blocks come first in the array and, with the
    /// default `display: "omitted"`, carry no text — so we skip past them.
    var firstText: String? {
        content.first(where: { $0.type == "text" && !($0.text ?? "").isEmpty })?.text
    }

    struct StopDetails: Decodable {
        let type: String?
        let category: String?
        let explanation: String?
    }

    struct ResponseBlock: Decodable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }

        /// Rough running cost at the given model's list pricing.
        func estimatedUSD(for model: ClaudeModel) -> Double {
            let inputRate = model.inputPricePerMTok
            let input = Double((inputTokens ?? 0) + (cacheCreationInputTokens ?? 0)) / 1_000_000 * inputRate
            let cached = Double(cacheReadInputTokens ?? 0) / 1_000_000 * (inputRate * 0.1)
            let output = Double(outputTokens ?? 0) / 1_000_000 * model.outputPricePerMTok
            return input + cached + output
        }
    }
}

/// `{"type":"error","error":{"type":"...","message":"..."}}`
struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let type: String?
        let message: String?
    }
}
