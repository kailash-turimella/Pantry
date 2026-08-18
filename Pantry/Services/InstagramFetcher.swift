import Foundation

/// What we managed to pull off a reel URL, and how.
struct ReelContent: Equatable {
    let shortcode: String
    let caption: String
    let author: String?
    let thumbnail: Data?
    /// Which strategy produced the caption — shown in the UI so a thin
    /// extraction is explainable rather than mysterious.
    let strategy: String

    var hasUsableText: Bool { caption.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 }
}

enum InstagramError: LocalizedError, Equatable {
    case notAnInstagramURL
    case noCaptionFound
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAnInstagramURL:
            return "That doesn't look like an Instagram reel or post link."
        case .noCaptionFound:
            return "Couldn't read anything from that reel. It may be private, or Instagram may be blocking us — paste the caption in manually instead."
        case .network(let detail):
            return "Couldn't reach Instagram: \(detail)"
        }
    }
}

/// Pulls the caption (and cover image) off a public Instagram reel.
///
/// **This is the fragile part of the app, by some margin.** Instagram has no
/// supported API for this, so we try a chain of unofficial routes and fall back
/// to asking the user to paste the caption. Known limits:
///
/// - Private, deleted, or age-restricted reels return nothing.
/// - Only the caption and cover frame are available. If the recipe is *spoken*
///   in the video, or only shown as on-screen text mid-video, we won't see it.
///   Downloading the video to transcribe it would need signed CDN URLs that
///   aren't exposed here, so that's deliberately out of scope.
/// - The oEmbed endpoint is undocumented and unauthenticated. It works today
///   (verified against public posts) but Meta can change or gate it at any time,
///   which is exactly why the manual-paste path exists.
enum InstagramFetcher {

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    // MARK: - URL parsing

    /// Accepts reel, reels, p, and tv links, with or without query strings.
    static func shortcode(from url: String) -> String? {
        let pattern = #"instagram\.com/(?:[^/]+/)?(?:reels?|p|tv)/([A-Za-z0-9_-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(url.startIndex..., in: url)
        guard let match = regex.firstMatch(in: url, range: range),
              let codeRange = Range(match.range(at: 1), in: url) else { return nil }
        return String(url[codeRange])
    }

    // MARK: - Fetching

    static func fetch(urlString: String) async throws -> ReelContent {
        guard let code = shortcode(from: urlString) else { throw InstagramError.notAnInstagramURL }

        var lastNetworkError: String?

        // Strategy 1: the unauthenticated oEmbed endpoint. Returns the caption in
        // `title` plus the author and a thumbnail URL. Cleanest route when it works.
        do {
            if let content = try await fetchViaOEmbed(code: code) { return content }
        } catch let error as InstagramError {
            if case .network(let detail) = error { lastNetworkError = detail }
        }

        // Strategy 2: the lightweight embed page, which renders the caption for
        // logged-out viewers.
        do {
            if let content = try await fetchViaEmbed(code: code) { return content }
        } catch let error as InstagramError {
            if case .network(let detail) = error { lastNetworkError = detail }
        }

        // Strategy 3: og:description on the canonical page. Usually truncated,
        // but better than nothing.
        do {
            if let content = try await fetchViaOpenGraph(code: code) { return content }
        } catch let error as InstagramError {
            if case .network(let detail) = error { lastNetworkError = detail }
        }

        if let lastNetworkError { throw InstagramError.network(lastNetworkError) }
        throw InstagramError.noCaptionFound
    }

    private static func fetchViaOEmbed(code: String) async throws -> ReelContent? {
        let target = "https://www.instagram.com/reel/\(code)/"
        guard let encoded = target.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "https://www.instagram.com/api/v1/oembed/?url=\(encoded)")
        else { return nil }

        let data = try await get(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let author = json["author_name"] as? String
        var caption = (json["title"] as? String) ?? ""

        // Some responses leave `title` empty but embed the caption in the
        // blockquote markup instead.
        if caption.isEmpty, let html = json["html"] as? String {
            caption = stripHTML(html)
        }
        guard !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        var thumbnail: Data?
        if let thumbURL = (json["thumbnail_url"] as? String).flatMap(URL.init(string:)) {
            thumbnail = try? await get(thumbURL)
        }

        return ReelContent(
            shortcode: code, caption: caption, author: author,
            thumbnail: thumbnail, strategy: "oEmbed"
        )
    }

    private static func fetchViaEmbed(code: String) async throws -> ReelContent? {
        guard let url = URL(string: "https://www.instagram.com/reel/\(code)/embed/captioned/") else { return nil }
        let data = try await get(url)
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        // The embed page carries the caption inside a JSON blob as
        // "edge_media_to_caption":{"edges":[{"node":{"text":"..."}}]}
        if let caption = firstMatch(in: html, pattern: #""edge_media_to_caption".{0,120}?"text"\s*:\s*"((?:[^"\\]|\\.)*)""#),
           !caption.isEmpty {
            return ReelContent(
                shortcode: code, caption: unescapeJSONString(caption),
                author: firstMatch(in: html, pattern: #""owner".{0,200}?"username"\s*:\s*"([^"]+)""#),
                thumbnail: nil, strategy: "embed page"
            )
        }

        // Older embed markup puts it in a div.
        if let caption = firstMatch(in: html, pattern: #"class="Caption".*?</div>"#) {
            let text = stripHTML(caption)
            if !text.isEmpty {
                return ReelContent(shortcode: code, caption: text, author: nil,
                                   thumbnail: nil, strategy: "embed page")
            }
        }
        return nil
    }

    private static func fetchViaOpenGraph(code: String) async throws -> ReelContent? {
        guard let url = URL(string: "https://www.instagram.com/reel/\(code)/") else { return nil }
        let data = try await get(url)
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        guard let raw = firstMatch(in: html, pattern: #"<meta property="og:description" content="([^"]*)""#),
              !raw.isEmpty else { return nil }

        let caption = decodeHTMLEntities(raw)
        return ReelContent(shortcode: code, caption: caption, author: nil,
                           thumbnail: nil, strategy: "page metadata")
    }

    // MARK: - HTTP

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 25

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw InstagramError.network("HTTP \(http.statusCode)")
            }
            return data
        } catch let error as InstagramError {
            throw error
        } catch {
            throw InstagramError.network(error.localizedDescription)
        }
    }

    // MARK: - Text helpers

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let group = match.numberOfRanges > 1 ? 1 : 0
        guard let matchRange = Range(match.range(at: group), in: text) else { return nil }
        return String(text[matchRange])
    }

    private static func stripHTML(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression
        )
        return decodeHTMLEntities(withoutTags)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&#x27;": "'", "&nbsp;": " ", "&hellip;": "…",
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    private static func unescapeJSONString(_ text: String) -> String {
        // The caption arrives as a JSON string body; round-trip it through the
        // JSON decoder so \n and \uXXXX escapes resolve properly.
        if let data = "\"\(text)\"".data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        return text
    }
}
