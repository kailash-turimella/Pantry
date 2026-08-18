import Foundation
import SwiftData

@Model
final class ShoppingItem {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double?
    var unit: MeasureUnit = MeasureUnit.piece
    var isChecked: Bool = false
    var addedAt: Date = Date()
    /// Set when the item arrived from "add a recipe's missing ingredients".
    var sourceRecipeTitle: String?

    init(
        name: String,
        quantity: Double? = nil,
        unit: MeasureUnit = .piece,
        sourceRecipeTitle: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.sourceRecipeTitle = sourceRecipeTitle
        self.addedAt = Date()
    }

    var displayQuantity: String? {
        guard let quantity else { return nil }
        return unit.format(quantity)
    }

    var matchKey: String { IngredientMatcher.normalize(name) }
}
