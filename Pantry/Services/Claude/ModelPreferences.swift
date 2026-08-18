import Foundation

/// The models offered in Settings. Deliberately three — a cheap one, a balanced
/// one, and the strongest — rather than the full catalogue, which would just be
/// a decision you have to make four times with no basis.
enum ClaudeModel: String, CaseIterable, Identifiable, Sendable {
    case haiku45 = "claude-haiku-4-5"
    case sonnet5 = "claude-sonnet-5"
    case opus5 = "claude-opus-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku45: return "Haiku 4.5"
        case .sonnet5: return "Sonnet 5"
        case .opus5: return "Opus 5"
        }
    }

    var blurb: String {
        switch self {
        case .haiku45: return "Fastest and cheapest. Fine for lookups and short factual answers."
        case .sonnet5: return "Near-Opus quality for most work, at roughly half the price."
        case .opus5: return "The strongest option. Worth it when the input is messy or needs judgement."
        }
    }

    /// USD per million tokens, at list pricing.
    var inputPricePerMTok: Double {
        switch self {
        case .haiku45: return 1.0
        case .sonnet5: return 3.0
        case .opus5: return 5.0
        }
    }

    var outputPricePerMTok: Double {
        switch self {
        case .haiku45: return 5.0
        case .sonnet5: return 15.0
        case .opus5: return 25.0
        }
    }

    var priceLabel: String {
        "$\(Int(inputPricePerMTok))/$\(Int(outputPricePerMTok)) per Mtok"
    }
}

/// The four jobs Pantry uses the API for. Each one picks its own model, because
/// they aren't remotely the same difficulty.
enum ClaudeTask: String, CaseIterable, Identifiable, Sendable {
    case photoItems
    case shelfLife
    case recipeText
    case reelRecipe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photoItems: return "Reading photos"
        case .shelfLife: return "Estimating shelf life"
        case .recipeText: return "Parsing pasted recipes"
        case .reelRecipe: return "Extracting reel recipes"
        }
    }

    var summary: String {
        switch self {
        case .photoItems:
            return "Identifying groceries in a photo and reading dates off packaging."
        case .shelfLife:
            return "How long an unusual item keeps. Common items never reach the API."
        case .recipeText:
            return "Turning recipe text you've pasted in into ingredients and steps."
        case .reelRecipe:
            return "Pulling a recipe out of an Instagram caption."
        }
    }

    /// Which model this task defaults to, and why. The reasoning is shown in the
    /// picker so the recommendation is arguable rather than magic.
    var recommended: ClaudeModel {
        switch self {
        case .shelfLife: return .haiku45
        case .photoItems, .recipeText: return .sonnet5
        case .reelRecipe: return .opus5
        }
    }

    var recommendationReason: String {
        switch self {
        case .photoItems:
            return "Vision work, but groceries are obvious objects and you check every result before it saves. A bigger model mostly buys confidence on blurry shots."
        case .shelfLife:
            return "A short factual answer with one number in it. This is the one task where paying more changes almost nothing — and the built-in table already handles common items without any API call."
        case .recipeText:
            return "Pasted recipes are usually already structured, so this is mostly reformatting. The judgement calls are small: splitting \"2 cloves garlic, crushed\" into name, quantity, and note."
        case .reelRecipe:
            return "Much the hardest of the four. Captions are emoji, hashtags, and engagement bait, ingredients are often implied rather than listed, and the method is frequently missing entirely. The model has to infer structure and — more importantly — be honest about what wasn't in the caption instead of inventing a method."
        }
    }

    /// Roughly what one call costs, to make the trade-off concrete.
    func approximateCostLabel(for model: ClaudeModel) -> String {
        let inputTokens: Double
        let outputTokens: Double
        switch self {
        case .photoItems: inputTokens = 1_800; outputTokens = 400
        case .shelfLife: inputTokens = 300; outputTokens = 150
        case .recipeText: inputTokens = 1_200; outputTokens = 700
        case .reelRecipe: inputTokens = 2_200; outputTokens = 700
        }
        let cost = inputTokens / 1_000_000 * model.inputPricePerMTok
            + outputTokens / 1_000_000 * model.outputPricePerMTok
        return cost < 0.01
            ? "under a cent per use"
            : "about \(cost.formatted(.currency(code: "USD"))) per use"
    }
}

/// Per-task model choice, persisted in UserDefaults. Falls back to each task's
/// recommendation, so a fresh install is already sensibly configured.
enum ModelPreferences {
    private static func key(for task: ClaudeTask) -> String { "model.\(task.rawValue)" }

    static func model(for task: ClaudeTask) -> ClaudeModel {
        guard let raw = UserDefaults.standard.string(forKey: key(for: task)),
              let model = ClaudeModel(rawValue: raw)
        else { return task.recommended }
        return model
    }

    static func set(_ model: ClaudeModel, for task: ClaudeTask) {
        UserDefaults.standard.set(model.rawValue, forKey: key(for: task))
    }

    static func isUsingRecommendation(for task: ClaudeTask) -> Bool {
        model(for: task) == task.recommended
    }

    static func resetAll() {
        for task in ClaudeTask.allCases {
            UserDefaults.standard.removeObject(forKey: key(for: task))
        }
    }
}
