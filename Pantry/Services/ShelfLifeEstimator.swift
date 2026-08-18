import Foundation

/// Fills in an expiry date for items that don't have one printed.
///
/// Three tiers, cheapest first:
/// 1. `ShelfLifeRules` — an offline table of common groceries. Instant, free,
///    works on a plane. Covers most of a normal shop.
/// 2. A cached previous Claude answer for the same item name.
/// 3. Claude, for the long tail ("gochujang", "burrata", "kefir").
///
/// The rules table isn't just a cost optimisation: it makes the common path
/// deterministic, so "milk" is always 7 days rather than drifting between runs.
enum ShelfLifeEstimator {

    struct Result: Equatable {
        let estimate: ShelfLifeEstimate
        let usedClaude: Bool
    }

    private static let cacheKey = "shelflife.cache.v1"

    private struct CachedEstimate: Codable {
        let days: Int
        let note: String
    }

    private struct ClaudeEstimate: Decodable {
        let days: Int
        let storage: String
        let note: String
    }

    private static let system = """
    You estimate how long a food item stays good, for a kitchen app that warns \
    people before food goes to waste.

    Rules:
    - Assume the item was bought fresh today and is stored the normal way for \
    that food (fridge for perishables, cupboard for dry goods, as sold).
    - Be conservative. If a range is typical, return the low end. Telling someone \
    to use something a day early is a small cost; telling them a day late is a \
    wasted item or a bad meal.
    - days is counted from today. Use whole days. For very shelf-stable items \
    cap the answer at 730.
    - note is one short sentence a person would find useful, e.g. "Keeps about a \
    week in the fridge once opened."
    """

    private static var schema: JSONValue {
        Schema.object(
            properties: [
                "days": Schema.integer("Days from today until this should be used, erring on the early side."),
                "storage": Schema.string(
                    "Where this is assumed to be stored.",
                    enumValues: ["fridge", "freezer", "pantry", "counter"]
                ),
                "note": Schema.string("One short, practical sentence about keeping this item."),
            ],
            required: ["days", "storage", "note"]
        )
    }

    /// Returns an estimate, or `nil` if we genuinely can't produce one (offline
    /// with no rule match and no API key).
    static func estimate(for name: String, category: FoodCategory) async -> Result? {
        let key = IngredientMatcher.normalize(name)
        guard !key.isEmpty else { return nil }

        // 1. Offline rules.
        if let rule = ShelfLifeRules.estimate(for: name, category: nil) {
            return Result(estimate: rule, usedClaude: false)
        }

        // 2. Something Claude already told us about this item.
        if let cached = cachedEstimate(for: key) {
            return Result(
                estimate: ShelfLifeEstimate(days: cached.days, note: cached.note, isConservative: true),
                usedClaude: false
            )
        }

        // 3. Ask Claude.
        if APIKeyStore.hasKey {
            do {
                let prompt = """
                Item: \(name)
                Category: \(category.displayName)
                """
                let answer = try await ClaudeClient.shared.structured(
                    ClaudeEstimate.self,
                    task: .shelfLife,
                    schema: schema,
                    system: system,
                    messages: [.user(prompt)],
                    effort: .low,
                    maxTokens: 4_000
                )
                let days = max(1, min(answer.days, 730))
                cache(CachedEstimate(days: days, note: answer.note), for: key)
                return Result(
                    estimate: ShelfLifeEstimate(days: days, note: answer.note, isConservative: true),
                    usedClaude: true
                )
            } catch {
                // Fall through to the category guess rather than failing the save.
            }
        }

        // 4. Last resort: category default, clearly labelled as a guess.
        if let categoryRule = ShelfLifeRules.estimate(for: name, category: category) {
            return Result(estimate: categoryRule, usedClaude: false)
        }
        return Result(estimate: ShelfLifeRules.fallback(for: category), usedClaude: false)
    }

    // MARK: - Cache

    private static func cachedEstimate(for key: String) -> CachedEstimate? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: CachedEstimate].self, from: data)
        else { return nil }
        return cache[key]
    }

    private static func cache(_ estimate: CachedEstimate, for key: String) {
        var cache: [String: CachedEstimate] = [:]
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let existing = try? JSONDecoder().decode([String: CachedEstimate].self, from: data) {
            cache = existing
        }
        cache[key] = estimate
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    static func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
