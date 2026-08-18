import Foundation
import SwiftData

/// How a recipe got into the app. Shown on the detail screen so AI-extracted
/// recipes are visibly distinct from ones typed by hand.
enum RecipeSource: String, Codable, CaseIterable, Sendable {
    case manual
    case pastedText
    case instagramReel

    var displayName: String {
        switch self {
        case .manual: return "Added by hand"
        case .pastedText: return "From pasted text"
        case .instagramReel: return "From an Instagram reel"
        }
    }

    var symbolName: String {
        switch self {
        case .manual: return "square.and.pencil"
        case .pastedText: return "doc.on.clipboard"
        case .instagramReel: return "play.rectangle.on.rectangle"
        }
    }
}

@Model
final class Recipe {
    var id: UUID = UUID()
    var title: String = ""
    var summary: String?
    var servings: Int?
    var totalMinutes: Int?
    var steps: [String] = []
    var sourceRaw: String = RecipeSource.manual.rawValue
    var sourceURL: String?
    var sourceAuthor: String?
    var createdAt: Date = Date()
    var lastCookedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient] = []

    var source: RecipeSource {
        get { RecipeSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        title: String,
        summary: String? = nil,
        servings: Int? = nil,
        totalMinutes: Int? = nil,
        steps: [String] = [],
        source: RecipeSource = .manual,
        sourceURL: String? = nil,
        sourceAuthor: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.servings = servings
        self.totalMinutes = totalMinutes
        self.steps = steps
        self.sourceRaw = source.rawValue
        self.sourceURL = sourceURL
        self.sourceAuthor = sourceAuthor
        self.createdAt = Date()
    }

    /// Ingredients in the order the user (or the extractor) listed them.
    var orderedIngredients: [RecipeIngredient] {
        ingredients.sorted { $0.position < $1.position }
    }
}

@Model
final class RecipeIngredient {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double?
    var unit: MeasureUnit = MeasureUnit.piece
    var note: String?
    var isOptional: Bool = false
    var position: Int = 0
    var recipe: Recipe?

    init(
        name: String,
        quantity: Double? = nil,
        unit: MeasureUnit = .piece,
        note: String? = nil,
        isOptional: Bool = false,
        position: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.note = note
        self.isOptional = isOptional
        self.position = position
    }

    /// "200 g flour, sifted"
    var displayLine: String {
        var parts: [String] = []
        if let quantity { parts.append(unit.format(quantity)) }
        parts.append(name)
        var line = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if let note, !note.isEmpty { line += ", \(note)" }
        if isOptional { line += " (optional)" }
        return line
    }

    var matchKey: String { IngredientMatcher.normalize(name) }
}
