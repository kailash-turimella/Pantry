import Foundation
import SwiftData

/// Where an item's expiry date came from. Surfaced in the UI so an estimate is
/// never mistaken for something printed on the packaging.
enum ExpirySource: String, Codable, CaseIterable, Sendable {
    case manual        // typed in by the user
    case estimated     // rules table or Claude's shelf-life estimate
    case none          // no date at all

    var displayName: String {
        switch self {
        case .manual: return "Entered"
        case .estimated: return "Estimated"
        case .none: return "Not set"
        }
    }
}

@Model
final class InventoryItem {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double = 1
    var unit: MeasureUnit = MeasureUnit.piece
    var category: FoodCategory = FoodCategory.other
    var expiryDate: Date?
    var expirySourceRaw: String = ExpirySource.none.rawValue
    var estimateNote: String?
    var addedDate: Date = Date()
    var notes: String?

    var expirySource: ExpirySource {
        get { ExpirySource(rawValue: expirySourceRaw) ?? .none }
        set { expirySourceRaw = newValue.rawValue }
    }

    init(
        name: String,
        quantity: Double = 1,
        unit: MeasureUnit = .piece,
        category: FoodCategory = .other,
        expiryDate: Date? = nil,
        expirySource: ExpirySource = .none,
        estimateNote: String? = nil,
        notes: String? = nil,
        addedDate: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.expiryDate = expiryDate
        self.expirySourceRaw = expirySource.rawValue
        self.estimateNote = estimateNote
        self.notes = notes
        self.addedDate = addedDate
    }

    var status: ExpiryStatus { ExpiryStatus.status(for: expiryDate) }

    var quantityDescription: String { unit.format(quantity) }

    /// Normalized form used by the ingredient matcher; cached nowhere on purpose —
    /// pantries are small and this keeps the stored model dumb.
    var matchKey: String { IngredientMatcher.normalize(name) }
}
