import Foundation

/// Decides whether a recipe ingredient and a pantry item are "the same thing".
///
/// Deliberately rule-based rather than an API call: it runs on every list
/// refresh, needs to be instant and offline, and the failure modes are easy to
/// reason about. The interesting part is `formTokens` — words that change what
/// an ingredient *is* rather than just describing it, which is what stops
/// "peanut" from matching "peanut butter".
enum IngredientMatcher {

    /// Words that describe preparation, size, or quality. Dropping these makes
    /// "2 finely chopped large ripe tomatoes" and "tomato" line up.
    private static let noiseWords: Set<String> = [
        "fresh", "freshly", "chopped", "diced", "minced", "sliced", "ground",
        "large", "small", "medium", "big", "ripe", "organic", "raw", "cooked",
        "boneless", "skinless", "whole", "halved", "quartered", "grated",
        "shredded", "peeled", "crushed", "drained", "rinsed", "packed",
        "plus", "extra", "roughly", "finely", "thinly", "thickly", "cold",
        "warm", "hot", "room", "temperature", "good", "quality", "best",
        "of", "a", "an", "the", "to", "for", "into", "and", "or", "with",
        "taste", "optional", "about", "approximately", "cut", "trimmed",
        "washed", "beaten", "softened", "melted", "divided", "level", "heaped",
    ]

    /// Words that mark a *different product*, not a variation of the same one.
    /// If one side has one of these and the other doesn't, they are not a match.
    private static let formTokens: Set<String> = [
        "paste", "sauce", "puree", "powder", "juice", "stock", "broth",
        "extract", "oil", "vinegar", "flour", "milk", "butter", "cream",
        "cheese", "yogurt", "yoghurt", "syrup", "jam", "honey", "wine",
        "seed", "leaf", "zest", "peel", "meal", "starch", "water", "essence",
    ]

    // MARK: - Normalization

    /// Lower-cases, strips prep words and punctuation, and singularizes.
    /// The result is the key both `InventoryItem` and `RecipeIngredient` expose.
    static func normalize(_ raw: String) -> String {
        tokens(raw).joined(separator: " ")
    }

    static func tokens(_ raw: String) -> [String] {
        var text = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        // Drop parenthetical asides: "flour (plain)" -> "flour"
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") {
            text.removeSubrange(open...close)
        }
        // Anything after a comma is almost always a prep note: "onion, diced"
        if let comma = text.firstIndex(of: ",") { text = String(text[..<comma]) }

        let separators = CharacterSet.alphanumerics.inverted
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { Double($0) == nil }           // strip bare numbers
            .filter { !noiseWords.contains($0) }
            .map(singularize)
            .filter { !$0.isEmpty }
    }

    static func singularize(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") || word.hasSuffix("ses") || word.hasSuffix("hes") || word.hasSuffix("xes") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("ss") || word.hasSuffix("us") || word.hasSuffix("is") { return word }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }

    // MARK: - Matching

    /// 0 = unrelated, 1 = identical. Anything at or above `matchThreshold` counts
    /// as "you already have this".
    static let matchThreshold = 0.6

    static func score(_ lhs: String, _ rhs: String) -> Double {
        let a = Set(tokens(lhs))
        let b = Set(tokens(rhs))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1.0 }

        // Subset match ("chicken" vs "chicken breast") — but only when the extra
        // words don't turn it into a different product ("peanut" vs "peanut butter").
        let extras = a.isSubset(of: b) ? b.subtracting(a) : (b.isSubset(of: a) ? a.subtracting(b) : nil)
        if let extras {
            return extras.isDisjoint(with: formTokens) ? 0.9 : 0.0
        }

        // Otherwise fall back to overlap, and still refuse a form-token mismatch.
        let aForms = a.intersection(formTokens)
        let bForms = b.intersection(formTokens)
        guard aForms == bForms else { return 0 }

        let intersection = a.intersection(b).count
        guard intersection > 0 else { return 0 }
        let union = a.union(b).count
        return (Double(intersection) / Double(union)) * 0.85
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        score(lhs, rhs) >= matchThreshold
    }

    /// The pantry item that best satisfies `ingredientName`, if any.
    static func bestMatch(for ingredientName: String, in items: [InventoryItem]) -> InventoryItem? {
        var best: (item: InventoryItem, score: Double)?
        for item in items {
            let value = score(item.name, ingredientName)
            guard value >= matchThreshold else { continue }
            if best == nil || value > best!.score {
                best = (item, value)
            } else if value == best!.score, let current = best {
                // Tie-break toward whatever expires first, so cooking uses it up.
                if item.status < current.item.status { best = (item, value) }
            }
        }
        return best?.item
    }
}
