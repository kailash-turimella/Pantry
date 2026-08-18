import Foundation
import UIKit

/// One candidate item Claude spotted in a photo. Nothing here is saved until
/// the user has seen and approved it on the review screen.
struct ExtractedItem: Identifiable, Decodable, Equatable {
    var id = UUID()
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    /// ISO `yyyy-MM-dd`, only when a date is actually legible on the packaging.
    let printedExpiry: String?
    let confidence: String

    enum CodingKeys: String, CodingKey {
        case name, quantity, unit, category, confidence
        case printedExpiry = "printed_expiry"
    }

    var resolvedUnit: MeasureUnit { MeasureUnit.parse(unit) }
    var resolvedCategory: FoodCategory { FoodCategory.parse(category) }

    var resolvedExpiry: Date? {
        guard let printedExpiry, !printedExpiry.isEmpty else { return nil }
        return ExtractedItem.isoFormatter.date(from: printedExpiry)
    }

    var isLowConfidence: Bool { confidence.lowercased() == "low" }

    static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct PhotoExtractionResult: Decodable {
    let items: [ExtractedItem]
    /// Anything Claude wants to flag — blurry photo, ambiguous product, etc.
    let notes: String?
}

/// Photo → candidate pantry items.
enum PhotoItemExtractor {

    private static let system = """
    You identify grocery items in photos for a kitchen inventory app.

    Rules:
    - List each distinct product once. If you see six eggs in a carton, that is \
    one item: name "eggs", quantity 6, unit "piece".
    - Use the name a person would write on a shopping list ("cheddar", "greek \
    yogurt"), not marketing copy from the packaging. Skip brand names unless the \
    brand is the only way to identify the product.
    - Only fill in printed_expiry if a use-by or best-before date is genuinely \
    legible in the image. Never infer or guess one from the product type — the \
    app estimates shelf life separately. Use yyyy-MM-dd.
    - Set confidence to "low" when the item is partly hidden, out of focus, or \
    you are unsure what it is. The user reviews everything before it is saved, so \
    a low-confidence guess is more useful than omitting the item.
    - Ignore non-food objects, packaging that is clearly empty, and anything that \
    is part of the kitchen rather than the shopping (pans, utensils, appliances).
    - If there is no food in the photo, return an empty items array and explain \
    in notes.
    """

    private static var schema: JSONValue {
        Schema.object(
            properties: [
                "items": Schema.array(
                    of: Schema.object(
                        properties: [
                            "name": Schema.string("Short, plain name for the item."),
                            "quantity": Schema.number("How many/much is visible. Use 1 if unclear."),
                            "unit": Schema.string(
                                "Unit for the quantity.",
                                enumValues: MeasureUnit.allCases.map(\.rawValue)
                            ),
                            "category": Schema.string(
                                "Best-fitting storage category.",
                                enumValues: FoodCategory.allCases.map(\.rawValue)
                            ),
                            "printed_expiry": Schema.nullable(
                                "string",
                                "Expiry printed on the packaging as yyyy-MM-dd, or null if none is legible."
                            ),
                            "confidence": Schema.string(
                                "How sure you are about this identification.",
                                enumValues: ["high", "medium", "low"]
                            ),
                        ],
                        required: ["name", "quantity", "unit", "category", "printed_expiry", "confidence"]
                    )
                ),
                "notes": Schema.nullable("string", "Anything the user should know about this photo, or null."),
            ],
            required: ["items", "notes"]
        )
    }

    /// Sends one or more photos and returns candidates for the review screen.
    static func extract(from images: [UIImage]) async throws -> PhotoExtractionResult {
        guard !images.isEmpty else { return PhotoExtractionResult(items: [], notes: nil) }

        var blocks: [ContentBlock] = images.compactMap { image in
            guard let prepared = ImagePreparer.prepare(image) else { return nil }
            return .image(base64: prepared.base64, mediaType: prepared.mediaType)
        }
        guard !blocks.isEmpty else { throw ClaudeError.emptyResponse }

        blocks.append(.text(
            images.count == 1
                ? "What groceries are in this photo?"
                : "What groceries are in these \(images.count) photos? Treat them as one shopping trip and don't list the same physical item twice."
        ))

        return try await ClaudeClient.shared.structured(
            PhotoExtractionResult.self,
            task: .photoItems,
            schema: schema,
            system: system,
            messages: [.user(blocks)],
            effort: .low,
            maxTokens: 8_000
        )
    }
}
