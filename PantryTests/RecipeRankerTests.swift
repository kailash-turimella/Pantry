import XCTest
@testable import Pantry

final class RecipeRankerTests: XCTestCase {

    private func date(inDays days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date())!
    }

    private func makeRecipe(_ title: String, ingredients: [String]) -> Recipe {
        let recipe = Recipe(title: title)
        recipe.ingredients = ingredients.enumerated().map { index, name in
            let ingredient = RecipeIngredient(name: name, position: index)
            ingredient.recipe = recipe
            return ingredient
        }
        return recipe
    }

    // MARK: - The core requirement

    /// More expiring ingredients used == higher rank, not merely "contains one".
    func testRecipeUsingMoreExpiringItemsRanksHigher() {
        let inventory = [
            InventoryItem(name: "spinach", category: .produce, expiryDate: date(inDays: 1)),
            InventoryItem(name: "mushrooms", category: .produce, expiryDate: date(inDays: 1)),
            InventoryItem(name: "cream", category: .dairy, expiryDate: date(inDays: 2)),
            InventoryItem(name: "rice", category: .pantry, expiryDate: date(inDays: 300)),
        ]

        let usesThree = makeRecipe("Creamy mushroom spinach", ingredients: ["spinach", "mushrooms", "cream"])
        let usesOne = makeRecipe("Spinach rice", ingredients: ["spinach", "rice"])

        let ranked = RecipeRanker.rank(recipes: [usesOne, usesThree], inventory: inventory)
        XCTAssertEqual(ranked.first?.recipe.title, "Creamy mushroom spinach")
    }

    func testSoonerExpiryOutranksLaterExpiry() {
        let inventory = [
            InventoryItem(name: "salmon", category: .seafood, expiryDate: date(inDays: 1)),
            InventoryItem(name: "carrots", category: .produce, expiryDate: date(inDays: 18)),
        ]

        let urgent = makeRecipe("Baked salmon", ingredients: ["salmon"])
        let relaxed = makeRecipe("Carrot soup", ingredients: ["carrots"])

        let ranked = RecipeRanker.rank(recipes: [relaxed, urgent], inventory: inventory)
        XCTAssertEqual(ranked.first?.recipe.title, "Baked salmon")
    }

    /// A recipe you're missing most of shouldn't beat one you can actually cook.
    func testCoveragePenalisesRecipesYouCannotMake() {
        let inventory = [
            InventoryItem(name: "spinach", category: .produce, expiryDate: date(inDays: 1)),
        ]

        let makeable = makeRecipe("Wilted spinach", ingredients: ["spinach"])
        let mostlyMissing = makeRecipe(
            "Elaborate pie",
            ingredients: ["spinach", "feta", "filo", "pine nuts", "dill", "egg"]
        )

        let ranked = RecipeRanker.rank(recipes: [mostlyMissing, makeable], inventory: inventory)
        XCTAssertEqual(ranked.first?.recipe.title, "Wilted spinach")
    }

    func testExpiredFoodIsNotRewarded() {
        let inventory = [InventoryItem(name: "yogurt", category: .dairy, expiryDate: date(inDays: -3))]
        let recipe = makeRecipe("Yogurt bowl", ingredients: ["yogurt"])

        let match = RecipeRanker.match(recipe: recipe, inventory: inventory)
        XCTAssertEqual(match.score, 0, "Expired items must contribute no urgency weight")
    }

    // MARK: - Match bookkeeping

    func testMissingIngredientsAreReported() {
        let inventory = [InventoryItem(name: "pasta", category: .pantry)]
        let recipe = makeRecipe("Carbonara", ingredients: ["pasta", "eggs", "pancetta"])

        let match = RecipeRanker.match(recipe: recipe, inventory: inventory)
        XCTAssertEqual(match.matched.count, 1)
        XCTAssertEqual(Set(match.missing.map(\.name)), ["eggs", "pancetta"])
        XCTAssertFalse(match.canCookNow)
    }

    func testCanCookNowIgnoresOptionalIngredients() {
        let inventory = [InventoryItem(name: "pasta", category: .pantry)]
        let recipe = Recipe(title: "Buttered pasta")
        let pasta = RecipeIngredient(name: "pasta", position: 0)
        let parsley = RecipeIngredient(name: "parsley", isOptional: true, position: 1)
        pasta.recipe = recipe
        parsley.recipe = recipe
        recipe.ingredients = [pasta, parsley]

        let match = RecipeRanker.match(recipe: recipe, inventory: inventory)
        XCTAssertTrue(match.canCookNow)
    }

    /// One onion shouldn't satisfy three separate onion lines.
    func testOnePantryItemIsNotDoubleCounted() {
        let inventory = [InventoryItem(name: "onion", category: .produce)]
        let recipe = makeRecipe("Onion heavy", ingredients: ["onion", "onion"])

        let match = RecipeRanker.match(recipe: recipe, inventory: inventory)
        XCTAssertEqual(match.matched.count, 1)
        XCTAssertEqual(match.missing.count, 1)
    }
}
