import Foundation

/// One recipe scored against the current pantry.
struct RecipeMatch: Identifiable {
    let recipe: Recipe
    /// Ingredients you already have, paired with the pantry item that covers them.
    let matched: [(ingredient: RecipeIngredient, item: InventoryItem)]
    let missing: [RecipeIngredient]
    /// Subset of matched pantry items that need using up soon — the whole point.
    let expiringUsed: [InventoryItem]
    let score: Double

    var id: UUID { recipe.id }

    /// Fraction of required (non-optional) ingredients you already own.
    var coverage: Double {
        let required = recipe.ingredients.filter { !$0.isOptional }.count
        guard required > 0 else { return 0 }
        let have = matched.filter { !$0.ingredient.isOptional }.count
        return Double(have) / Double(required)
    }

    var canCookNow: Bool { missing.allSatisfy(\.isOptional) }
}

/// Ranks recipes so the ones that burn down your soonest-to-expire food float up.
///
/// The score is deliberately *not* "does this recipe contain the ingredient" —
/// it's a sum of per-ingredient urgency weights, scaled by how much of the
/// recipe you can actually make. A recipe that uses three items expiring
/// tomorrow beats one that uses a single item expiring tomorrow, and a recipe
/// you're missing eight ingredients for gets pushed down even if it would use
/// something urgent.
enum RecipeRanker {

    /// How much each pantry item contributes, by urgency.
    static func urgencyWeight(for status: ExpiryStatus) -> Double {
        switch status {
        case .expired: return 0.0        // don't cook with it; don't reward it
        case .today: return 6.0
        case .soon(let days): return days <= 1 ? 5.0 : 4.0
        case .thisWeek: return 2.0
        case .fresh(let days): return days <= 14 ? 1.0 : 0.5
        case .unknown: return 0.4
        }
    }

    /// Recipes you can't meaningfully make get suppressed rather than dropped,
    /// so a near-miss with one urgent ingredient still shows up below the rest.
    private static func coverageMultiplier(_ coverage: Double) -> Double {
        0.35 + 0.65 * coverage
    }

    static func rank(recipes: [Recipe], inventory: [InventoryItem]) -> [RecipeMatch] {
        recipes
            .map { match(recipe: $0, inventory: inventory) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.coverage != rhs.coverage { return lhs.coverage > rhs.coverage }
                return lhs.recipe.title.localizedCaseInsensitiveCompare(rhs.recipe.title) == .orderedAscending
            }
    }

    static func match(recipe: Recipe, inventory: [InventoryItem]) -> RecipeMatch {
        var matched: [(ingredient: RecipeIngredient, item: InventoryItem)] = []
        var missing: [RecipeIngredient] = []
        var claimed = Set<UUID>()

        for ingredient in recipe.orderedIngredients {
            // Don't let one jar of tomatoes satisfy three different lines.
            let available = inventory.filter { !claimed.contains($0.id) }
            if let item = IngredientMatcher.bestMatch(for: ingredient.name, in: available) {
                matched.append((ingredient, item))
                claimed.insert(item.id)
            } else {
                missing.append(ingredient)
            }
        }

        let expiringUsed = matched.map(\.item).filter { $0.status.needsAttention }
        let urgency = matched.reduce(0.0) { $0 + urgencyWeight(for: $1.item.status) }

        let required = recipe.ingredients.filter { !$0.isOptional }.count
        let have = matched.filter { !$0.ingredient.isOptional }.count
        let coverage = required > 0 ? Double(have) / Double(required) : 0

        return RecipeMatch(
            recipe: recipe,
            matched: matched,
            missing: missing,
            expiringUsed: expiringUsed,
            score: urgency * coverageMultiplier(coverage)
        )
    }
}
