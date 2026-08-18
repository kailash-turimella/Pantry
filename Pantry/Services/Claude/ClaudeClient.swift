import Foundation
import os

/// Thin async wrapper over the Anthropic Messages API.
///
/// There is no official Swift SDK, so this talks raw HTTP to
/// `POST /v1/messages`. Everything the app asks Claude for goes through
/// `structured(_:)`, which uses structured outputs (`output_config.format`) so
/// the reply is guaranteed to parse into a Swift type instead of being
/// hand-scraped out of prose.
actor ClaudeClient {
    static let shared = ClaudeClient()

    /// Each task picks its own model in Settings — see `ModelPreferences`.
    /// Thinking is on by default on these models, so we don't send a `thinking`
    /// block; `effort` is the dial that keeps extraction calls quick and cheap.

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"
    private static let maxAttempts = 3

    private let session: URLSession
    private let logger = Logger(subsystem: "com.kailash.Pantry", category: "claude")

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            // Thinking models can take a while on a cold call; the default 60s
            // is tight for recipe parsing at medium effort.
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 180
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    /// Sends a request whose reply is constrained to `schema`, and decodes it into `T`.
    func structured<T: Decodable>(
        _ type: T.Type,
        task: ClaudeTask,
        schema: JSONValue,
        system: String,
        messages: [RequestMessage],
        effort: Effort = .low,
        maxTokens: Int = 8_000
    ) async throws -> T {
        let model = ModelPreferences.model(for: task)
        let request = MessagesRequest(
            model: model.rawValue,
            maxTokens: maxTokens,
            system: system,
            messages: messages,
            outputConfig: OutputConfig(
                effort: effort.rawValue,
                format: OutputConfig.OutputFormat(schema: schema)
            )
        )

        let response = try await send(request, model: model)
        guard let json = response.firstText, let data = json.data(using: .utf8) else {
            throw ClaudeError.emptyResponse
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Structured decode failed: \(String(describing: error), privacy: .public)")
            throw ClaudeError.decoding(String(describing: error))
        }
    }

    // MARK: - Transport

    private func send(_ body: MessagesRequest, model: ClaudeModel) async throws -> MessagesResponse {
        let apiKey = try APIKeyStore.requireKey()
        let payload = try JSONEncoder().encode(body)

        var lastError: ClaudeError = .emptyResponse

        for attempt in 1...Self.maxAttempts {
            do {
                return try await performRequest(payload: payload, apiKey: apiKey, model: model)
            } catch let error as ClaudeError where error.isRetryable && attempt < Self.maxAttempts {
                lastError = error
                let delay = Self.backoffDelay(attempt: attempt, error: error)
                logger.notice("Retrying after \(delay, format: .fixed(precision: 1))s (attempt \(attempt))")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch let error as ClaudeError {
                throw error
            } catch {
                throw ClaudeError.network(error.localizedDescription)
            }
        }

        throw lastError
    }

    private func performRequest(payload: Data, apiKey: String, model: ClaudeModel) async throws -> MessagesResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = payload

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.network("Malformed response")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapHTTPError(status: http.statusCode, headers: http, data: data)
        }

        let decoded: MessagesResponse
        do {
            decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw ClaudeError.decoding(String(describing: error))
        }

        // Opus 5 ships elevated safety classifiers: a decline is a *successful*
        // HTTP 200 with stop_reason "refusal", so this has to be checked before
        // anyone touches `content`.
        if decoded.stopReason == "refusal" {
            throw ClaudeError.refused(
                category: decoded.stopDetails?.category,
                explanation: decoded.stopDetails?.explanation
            )
        }
        if decoded.stopReason == "max_tokens" {
            throw ClaudeError.truncated
        }

        if let usage = decoded.usage {
            await UsageTracker.shared.record(usage, model: model)
            logger.debug("in=\(usage.inputTokens ?? 0) out=\(usage.outputTokens ?? 0)")
        }

        return decoded
    }

    // MARK: - Errors & backoff

    private static func mapHTTPError(status: Int, headers: HTTPURLResponse, data: Data) -> ClaudeError {
        let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let message = envelope?.error.message ?? String(data: data, encoding: .utf8) ?? "Unknown error"
        let type = envelope?.error.type

        switch status {
        case 401, 403:
            return .unauthorized
        case 429:
            let retryAfter = (headers.value(forHTTPHeaderField: "retry-after")).flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        case 500...:
            return .serverError(status: status, message: message)
        default:
            return .badRequest(type: type, message: message)
        }
    }

    private static func backoffDelay(attempt: Int, error: ClaudeError) -> TimeInterval {
        if case .rateLimited(let retryAfter) = error, let retryAfter {
            return min(retryAfter, 30)
        }
        let base = pow(2.0, Double(attempt - 1))          // 1s, 2s, 4s
        return base + Double.random(in: 0...0.4)          // jitter
    }
}

/// Keeps a rough running total of API spend so the Settings screen can show it.
/// Personal app, personal credit card — worth seeing.
actor UsageTracker {
    static let shared = UsageTracker()

    private let defaultsKey = "claude.usage.totalUSD"
    private let callsKey = "claude.usage.callCount"

    func record(_ usage: MessagesResponse.Usage, model: ClaudeModel) {
        let defaults = UserDefaults.standard
        let total = defaults.double(forKey: defaultsKey) + usage.estimatedUSD(for: model)
        defaults.set(total, forKey: defaultsKey)
        defaults.set(defaults.integer(forKey: callsKey) + 1, forKey: callsKey)
    }

    nonisolated var totalUSD: Double { UserDefaults.standard.double(forKey: "claude.usage.totalUSD") }
    nonisolated var callCount: Int { UserDefaults.standard.integer(forKey: "claude.usage.callCount") }

    nonisolated func reset() {
        UserDefaults.standard.removeObject(forKey: "claude.usage.totalUSD")
        UserDefaults.standard.removeObject(forKey: "claude.usage.callCount")
    }
}
