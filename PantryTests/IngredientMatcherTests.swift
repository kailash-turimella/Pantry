import XCTest
@testable import Pantry

final class IngredientMatcherTests: XCTestCase {

    // MARK: - Normalization

    func testStripsPreparationAndSizeWords() {
        XCTAssertEqual(IngredientMatcher.normalize("2 finely chopped large ripe tomatoes"), "tomato")
        XCTAssertEqual(IngredientMatcher.normalize("Fresh Basil"), "basil")
        XCTAssertEqual(IngredientMatcher.normalize("boneless skinless chicken thighs"), "chicken thigh")
    }

    func testDropsParentheticalsAndTrailingNotes() {
        XCTAssertEqual(IngredientMatcher.normalize("flour (plain)"), "flour")
        XCTAssertEqual(IngredientMatcher.normalize("onion, diced"), "onion")
    }

    func testSingularization() {
        XCTAssertEqual(IngredientMatcher.singularize("tomatoes"), "tomato")
        XCTAssertEqual(IngredientMatcher.singularize("berries"), "berry")
        XCTAssertEqual(IngredientMatcher.singularize("dishes"), "dish")
        // Words that merely end in "s" must survive intact.
        XCTAssertEqual(IngredientMatcher.singularize("hummus"), "hummus")
        XCTAssertEqual(IngredientMatcher.singularize("glass"), "glass")
    }

    // MARK: - Matching

    func testExactAndPluralMatches() {
        XCTAssertTrue(IngredientMatcher.matches("Tomatoes", "tomato"))
        XCTAssertTrue(IngredientMatcher.matches("egg", "2 eggs"))
    }

    func testSpecificPantryItemSatisfiesGenericIngredient() {
        XCTAssertTrue(IngredientMatcher.matches("chicken breast", "chicken"))
        XCTAssertTrue(IngredientMatcher.matches("cherry tomatoes", "tomato"))
        XCTAssertTrue(IngredientMatcher.matches("extra virgin olive oil", "olive oil"))
    }

    /// The interesting case: a shared word doesn't mean a shared ingredient.
    func testFormTokensPreventFalseMatches() {
        XCTAssertFalse(IngredientMatcher.matches("peanut", "peanut butter"))
        XCTAssertFalse(IngredientMatcher.matches("coconut", "coconut milk"))
        XCTAssertFalse(IngredientMatcher.matches("tomato", "tomato paste"))
        XCTAssertFalse(IngredientMatcher.matches("chicken", "chicken stock"))
        XCTAssertFalse(IngredientMatcher.matches("almond", "almond flour"))
    }

    func testUnrelatedItemsDoNotMatch() {
        XCTAssertFalse(IngredientMatcher.matches("egg", "eggplant"))
        XCTAssertFalse(IngredientMatcher.matches("butter", "butternut squash"))
        XCTAssertFalse(IngredientMatcher.matches("rice", "rice vinegar"))
        XCTAssertFalse(IngredientMatcher.matches("milk", "flour"))
    }

    func testBestMatchPrefersTheItemExpiringSoonest() {
        let soon = InventoryItem(
            name: "chicken breast", category: .meat,
            expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())
        )
        let later = InventoryItem(
            name: "chicken breast", category: .meat,
            expiryDate: Calendar.current.date(byAdding: .day, value: 20, to: Date())
        )

        let best = IngredientMatcher.bestMatch(for: "chicken breast", in: [later, soon])
        XCTAssertIdentical(best, soon)
    }

    func testBestMatchReturnsNilWhenNothingIsClose() {
        let items = [InventoryItem(name: "rice"), InventoryItem(name: "soy sauce")]
        XCTAssertNil(IngredientMatcher.bestMatch(for: "lamb shoulder", in: items))
    }
}
