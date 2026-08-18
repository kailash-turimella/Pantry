import Foundation

/// A recipe Claude has pulled out of unstructured input. This is *not* a
/// `Recipe` — it only becomes one after the user approves it on the confirm
/// screen.
struct ParsedRecipe: Decodable, Equatable {
    let title: String
    let summary: String?
    let servings: Int?
    let totalMinutes: Int?
    let ingredients: [ParsedIngredient]
    let steps: [String]
    /// How complete the source material was. Drives the warning banner on the
    /// review screen.
    let confidence: String
    /// What Claude couldn't determine, if anything.
    let missingInformation: String?

    enum CodingKeys: String, CodingKey {
        case title, summary, servings, ingredients, steps, confidence
        case totalMinutes = "total_minutes"
        case missingInformation = "missing_information"
    }

    var isLowConfidence: Bool { confidence.lowercased() != "high" }

    static let empty = ParsedRecipe(
        title: "", summary: nil, servings: nil, totalMinutes: nil,
        ingredients: [], steps: [], confidence: "low", missingInformation: nil
    )
}

struct ParsedIngredient: Decodable, Equatable, Identifiable {
    var id = UUID()
    let name: String
    let quantity: Double?
    let unit: String
    let note: String?
    let isOptional: Bool

    enum CodingKeys: String, CodingKey {
        case name, quantity, unit, note
        case isOptional = "is_optional"
    }

    var resolvedUnit: MeasureUnit { MeasureUnit.parse(unit) }
}

/// Shared schema + prompt fragments for the two recipe importers.
enum RecipeExtraction {

    static var schema: JSONValue {
        Schema.object(
            properties: [
                "title": Schema.string("Name of the dish."),
                "summary": Schema.nullable("string", "One sentence describing the dish, or null."),
                "servings": Schema.nullable("integer", "How many people it serves, or null if not stated."),
                "total_minutes": Schema.nullable("integer", "Total time in minutes, or null if not stated."),
                "ingredients": Schema.array(
                    of: Schema.object(
                        properties: [
                            "name": Schema.string("The ingredient itself, without quantity or preparation. e.g. \"onion\", not \"1 large onion, diced\"."),
                            "quantity": Schema.nullable("number", "Numeric amount, or null if not given. Convert fractions to decimals."),
                            "unit": Schema.string(
                                "Unit for the quantity.",
                                enumValues: MeasureUnit.allCases.map(\.rawValue)
                            ),
                            "note": Schema.nullable("string", "Preparation or qualifier, e.g. \"finely diced\". Null if none."),
                            "is_optional": Schema.boolean("True if the recipe marks this as optional or \"to taste\"."),
                        ],
                        required: ["name", "quantity", "unit", "note", "is_optional"]
                    )
                ),
                "steps": Schema.array(
                    of: Schema.string("One step of the method, as a complete instruction."),
                    description: "Ordered method steps."
                ),
                "confidence": Schema.string(
                    "How complete and reliable this extraction is.",
                    enumValues: ["high", "medium", "low"]
                ),
                "missing_information": Schema.nullable(
                    "string",
                    "What the source didn't say that a cook would need, or null if nothing."
                ),
            ],
            required: ["title", "summary", "servings", "total_minutes", "ingredients", "steps", "confidence", "missing_information"]
        )
    }

    static let sharedRules = """
    - Put the ingredient itself in name and everything else in note: "2 cloves \
    garlic, crushed" becomes name "garlic", quantity 2, unit "piece", note \
    "cloves, crushed".
    - Convert fractions and ranges to a single decimal: "1½" becomes 1.5, \
    "2-3 tbsp" becomes 2.
    - Never invent quantities, steps, or timings that the source doesn't \
    contain. Leave them null and say so in missing_information. The user reviews \
    everything before it is saved, so an honest gap is better than a plausible \
    guess.
    - Set confidence to "high" only when the source clearly lists both \
    ingredients and a method. Use "medium" when you had to infer some structure, \
    and "low" when the source is fragmentary.
    """
}

/// Free text (a pasted recipe, a screenshot transcript, a note) → structured recipe.
enum RecipeTextParser {

    private static let system = """
    You turn pasted recipe text into structured data for a personal cooking app.

    \(RecipeExtraction.sharedRules)
    - If the text contains several recipes, extract only the first one and note \
    that in missing_information.
    """

    static func parse(_ text: String) async throws -> ParsedRecipe {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClaudeError.emptyResponse }

        return try await ClaudeClient.shared.structured(
            ParsedRecipe.self,
            task: .recipeText,
            schema: RecipeExtraction.schema,
            system: system,
            messages: [.user("Recipe text:\n\n\(trimmed)")],
            effort: .low,
            maxTokens: 12_000
        )
    }
}
