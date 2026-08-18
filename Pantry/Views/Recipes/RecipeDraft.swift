import Foundation
import SwiftData

/// Mutable, view-friendly recipe. Manual entry, editing an existing recipe, and
/// confirming an AI extraction all edit one of these — which is what guarantees
/// the "you always review it before it's saved" rule holds for every path.
struct RecipeDraft {
    var title = ""
    var summary = ""
    var servingsText = ""
    var minutesText = ""
    var ingredients: [IngredientDraft] = []
    var steps: [String] = []
    var source: RecipeSource = .manual
    var sourceURL: String?
    var sourceAuthor: String?

    /// Set when Claude flagged the extraction as incomplete.
    var extractionWarning: String?
    var isLowConfidence = false

    init() {
        ingredients = [IngredientDraft()]
        steps = [""]
    }

    /// From a Claude extraction — the confirm screen's starting point.
    init(parsed: ParsedRecipe, source: RecipeSource, sourceURL: String? = nil, author: String? = nil) {
        title = parsed.title
        summary = parsed.summary ?? ""
        servingsText = parsed.servings.map(String.init) ?? ""
        minutesText = parsed.totalMinutes.map(String.init) ?? ""
        ingredients = parsed.ingredients.map(IngredientDraft.init(parsed:))
        steps = parsed.steps.isEmpty ? [""] : parsed.steps
        self.source = source
        self.sourceURL = sourceURL
        sourceAuthor = author
        extractionWarning = parsed.missingInformation
        isLowConfidence = parsed.isLowConfidence

        if ingredients.isEmpty { ingredients = [IngredientDraft()] }
    }

    /// From a stored recipe, for editing.
    init(recipe: Recipe) {
        title = recipe.title
        summary = recipe.summary ?? ""
        servingsText = recipe.servings.map(String.init) ?? ""
        minutesText = recipe.totalMinutes.map(String.init) ?? ""
        ingredients = recipe.orderedIngredients.map(IngredientDraft.init(ingredient:))
        steps = recipe.steps.isEmpty ? [""] : recipe.steps
        source = recipe.source
        sourceURL = recipe.sourceURL
        sourceAuthor = recipe.sourceAuthor

        if ingredients.isEmpty { ingredients = [IngredientDraft()] }
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && ingredients.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var cleanedSteps: [String] {
        steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var cleanedIngredients: [IngredientDraft] {
        ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Creates a new stored recipe from this draft.
    @discardableResult
    func insert(into context: ModelContext) -> Recipe {
        let recipe = Recipe(
            title: title.trimmingCharacters(in: .whitespaces),
            summary: summary.isEmpty ? nil : summary,
            servings: Int(servingsText),
            totalMinutes: Int(minutesText),
            steps: cleanedSteps,
            source: source,
            sourceURL: sourceURL,
            sourceAuthor: sourceAuthor
        )
        context.insert(recipe)

        for (index, draft) in cleanedIngredients.enumerated() {
            let ingredient = draft.makeIngredient(position: index)
            ingredient.recipe = recipe
            context.insert(ingredient)
        }
        return recipe
    }

    /// Overwrites an existing recipe with this draft.
    func apply(to recipe: Recipe, in context: ModelContext) {
        recipe.title = title.trimmingCharacters(in: .whitespaces)
        recipe.summary = summary.isEmpty ? nil : summary
        recipe.servings = Int(servingsText)
        recipe.totalMinutes = Int(minutesText)
        recipe.steps = cleanedSteps

        for existing in recipe.ingredients { context.delete(existing) }
        recipe.ingredients = []

        for (index, draft) in cleanedIngredients.enumerated() {
            let ingredient = draft.makeIngredient(position: index)
            ingredient.recipe = recipe
            context.insert(ingredient)
        }
    }
}

struct IngredientDraft: Identifiable {
    let id = UUID()
    var name = ""
    /// Kept as text so the field can be empty rather than forced to 0.
    var quantityText = ""
    var unit: MeasureUnit = .piece
    var note = ""
    var isOptional = false

    init() {}

    init(parsed: ParsedIngredient) {
        name = parsed.name
        quantityText = parsed.quantity.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
        unit = parsed.resolvedUnit
        note = parsed.note ?? ""
        isOptional = parsed.isOptional
    }

    init(ingredient: RecipeIngredient) {
        name = ingredient.name
        quantityText = ingredient.quantity.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
        unit = ingredient.unit
        note = ingredient.note ?? ""
        isOptional = ingredient.isOptional
    }

    func makeIngredient(position: Int) -> RecipeIngredient {
        RecipeIngredient(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: Double(quantityText.replacingOccurrences(of: ",", with: ".")),
            unit: unit,
            note: note.isEmpty ? nil : note,
            isOptional: isOptional,
            position: position
        )
    }
}
