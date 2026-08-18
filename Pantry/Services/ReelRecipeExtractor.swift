import Foundation

/// A reel import in progress: what we scraped, plus what Claude made of it.
struct ReelImport {
    let content: ReelContent
    let recipe: ParsedRecipe
}

/// Instagram reel URL → structured recipe, via caption (+ cover frame).
enum ReelRecipeExtractor {

    private static let system = """
    You turn Instagram reel captions into structured recipe data for a personal \
    cooking app.

    Reel captions are messy: emoji, hashtags, ingredient lists with no method, \
    engagement bait, and links. Extract only the recipe.

    \(RecipeExtraction.sharedRules)
    - Ignore hashtags, @mentions, follow/save/comment prompts, and links.
    - Emoji are often used as bullets or as the ingredient itself (🧄 = garlic). \
    Read them, then drop them from the output text.
    - Captions frequently list ingredients but describe the method only in the \
    video. If the method is missing or is a single vague line, still extract the \
    ingredients, set confidence to "low", and say in missing_information that the \
    method wasn't in the caption.
    - If a cover image is attached, use it only to confirm what the dish is or to \
    read on-screen text. Do not invent ingredients from how the food looks.
    - If the caption contains no recipe at all, return the dish name you can infer \
    as title, empty ingredients and steps, and confidence "low".
    """

    /// Fetches the reel and extracts a recipe. Throws `InstagramError` if the
    /// reel can't be read at all — the caller then offers manual paste.
    static func importReel(from urlString: String) async throws -> ReelImport {
        let content = try await InstagramFetcher.fetch(urlString: urlString)
        let recipe = try await extract(from: content)
        return ReelImport(content: content, recipe: recipe)
    }

    /// Runs the extraction against already-fetched content. Also used when the
    /// user pastes a caption by hand.
    static func extract(from content: ReelContent) async throws -> ParsedRecipe {
        var blocks: [ContentBlock] = []

        if let thumbnail = content.thumbnail, let prepared = ImagePreparer.prepare(data: thumbnail) {
            blocks.append(.image(base64: prepared.base64, mediaType: prepared.mediaType))
        }

        var prompt = "Instagram reel caption:\n\n\(content.caption)"
        if let author = content.author {
            prompt += "\n\nPosted by: @\(author)"
        }
        blocks.append(.text(prompt))

        return try await ClaudeClient.shared.structured(
            ParsedRecipe.self,
            task: .reelRecipe,
            schema: RecipeExtraction.schema,
            system: system,
            messages: [.user(blocks)],
            effort: .low,
            maxTokens: 12_000
        )
    }

    /// Manual-paste fallback for when every scrape strategy fails.
    static func extract(fromPastedCaption caption: String, sourceURL: String?) async throws -> ReelImport {
        let content = ReelContent(
            shortcode: sourceURL.flatMap(InstagramFetcher.shortcode(from:)) ?? "",
            caption: caption,
            author: nil,
            thumbnail: nil,
            strategy: "pasted by hand"
        )
        return ReelImport(content: content, recipe: try await extract(from: content))
    }
}
