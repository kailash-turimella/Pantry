import Foundation

enum ClaudeError: LocalizedError, Equatable {
    case missingAPIKey
    /// 4xx that won't succeed on retry.
    case badRequest(type: String?, message: String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(status: Int, message: String)
    /// Claude's safety classifiers declined the request (HTTP 200 + stop_reason "refusal").
    case refused(category: String?, explanation: String?)
    /// Hit `max_tokens` before finishing — the JSON we got back is incomplete.
    case truncated
    case emptyResponse
    case decoding(String)
    case network(String)

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .network: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Anthropic API key set. Add one in Settings."
        case .badRequest(_, let message):
            return "Claude rejected the request: \(message)"
        case .unauthorized:
            return "That API key was rejected. Check it in Settings."
        case .rateLimited:
            return "Rate limited by the API. Try again in a moment."
        case .serverError(let status, _):
            return "Claude is having trouble right now (HTTP \(status)). Try again shortly."
        case .refused(_, let explanation):
            return explanation.map { "Claude declined this request: \($0)" }
                ?? "Claude declined this request."
        case .truncated:
            return "The response was cut off before it finished. Try again, or split the input."
        case .emptyResponse:
            return "Claude returned nothing usable."
        case .decoding(let detail):
            return "Couldn't read Claude's response: \(detail)"
        case .network(let detail):
            return "Network problem: \(detail)"
        }
    }
}
