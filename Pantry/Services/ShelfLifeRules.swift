import Foundation

struct ShelfLifeEstimate: Equatable, Sendable {
    let days: Int
    let note: String
    let isConservative: Bool

    var suggestedDate: Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
    }
}

/// A small offline table of typical fridge/pantry life for common groceries.
///
/// This exists so the app doesn't burn an API call (or fail offline) on
/// "bananas". Claude is only consulted when nothing here matches — see
/// `ShelfLifeEstimator`. Numbers are deliberately on the conservative side:
/// telling you to eat something a day early is much cheaper than the opposite.
enum ShelfLifeRules {

    /// Normalized name -> typical days from purchase, stored as the user would keep it.
    private static let table: [String: Int] = [
        // Produce — fridge
        "spinach": 5, "lettuce": 6, "arugula": 4, "rocket": 4, "kale": 5,
        "herb": 5, "basil": 4, "coriander": 5, "cilantro": 5, "parsley": 7,
        "mint": 6, "dill": 5, "spring onion": 7, "scallion": 7,
        "mushroom": 6, "berry": 4, "strawberry": 4, "raspberry": 3,
        "blueberry": 8, "blackberry": 3, "grape": 8, "cherry": 6,
        "asparagus": 4, "broccoli": 7, "cauliflower": 8, "green bean": 6,
        "cucumber": 7, "courgette": 7, "zucchini": 7, "pepper": 9,
        "bell pepper": 9, "tomato": 6, "avocado": 4, "banana": 5,
        "peach": 4, "plum": 5, "mango": 5, "pineapple": 5, "melon": 6,
        "celery": 12, "carrot": 21, "cabbage": 21, "beetroot": 21, "beet": 21,
        "apple": 21, "orange": 14, "lemon": 21, "lime": 21, "grapefruit": 14,
        "potato": 30, "sweet potato": 25, "onion": 30, "garlic": 60,
        "ginger": 21, "squash": 30, "pumpkin": 30,

        // Dairy & eggs
        "milk": 7, "whole milk": 7, "skim milk": 7, "oat milk": 7,
        "almond milk": 7, "soy milk": 7, "cream": 7, "double cream": 7,
        "heavy cream": 7, "sour cream": 14, "creme fraiche": 14,
        "yogurt": 14, "yoghurt": 14, "greek yogurt": 14,
        "butter": 30, "egg": 21, "cottage cheese": 7, "ricotta": 7,
        "mozzarella": 7, "feta": 14, "cream cheese": 14, "parmesan": 45,
        "cheddar": 21, "cheese": 14, "halloumi": 21,

        // Meat & seafood (fridge, raw)
        "chicken": 2, "chicken breast": 2, "chicken thigh": 2, "turkey": 2,
        "beef": 3, "steak": 3, "mince": 2, "ground beef": 2, "lamb": 3,
        "pork": 3, "sausage": 3, "bacon": 7, "ham": 5, "salami": 14,
        "fish": 2, "salmon": 2, "tuna": 2, "cod": 2, "prawn": 2, "shrimp": 2,
        "mussel": 1, "scallop": 1, "tofu": 7, "tempeh": 10,

        // Bakery
        "bread": 5, "sourdough": 5, "baguette": 2, "bagel": 5, "tortilla": 14,
        "pita": 7, "croissant": 2, "cake": 4, "muffin": 4,

        // Cooked / leftovers
        "leftover": 3, "cooked rice": 3, "soup": 4, "stock": 4, "broth": 4,

        // Pantry staples — long, mostly a formality
        "rice": 540, "pasta": 540, "flour": 240, "sugar": 720, "salt": 1800,
        "oil": 365, "olive oil": 365, "vinegar": 720, "honey": 1800,
        "canned tomato": 540, "canned bean": 540, "bean": 540, "lentil": 540,
        "chickpea": 540, "oat": 300, "cereal": 180, "peanut butter": 180,
        "jam": 300, "soy sauce": 540, "mustard": 300, "ketchup": 300,
        "mayonnaise": 60, "spice": 540, "coffee": 180, "tea": 540,
        "nut": 120, "almond": 120, "walnut": 90, "chocolate": 300,
    ]

    /// Fallback when the name isn't in the table but the category is known.
    private static let categoryDefaults: [FoodCategory: Int] = [
        .produce: 7,
        .dairy: 10,
        .meat: 3,
        .seafood: 2,
        .bakery: 5,
        .frozen: 120,
        .leftovers: 3,
        .beverage: 14,
        .condiment: 180,
        .pantry: 365,
        .other: 14,
    ]

    /// Looks up a name, preferring the most specific entry that matches.
    /// Returns `nil` when we have no opinion at all — that's the signal to ask Claude.
    static func estimate(for name: String, category: FoodCategory? = nil) -> ShelfLifeEstimate? {
        let key = IngredientMatcher.normalize(name)
        guard !key.isEmpty else { return nil }

        if let days = table[key] {
            return ShelfLifeEstimate(days: days, note: "Typical shelf life for \(key).", isConservative: true)
        }

        // Longest matching multi-word entry wins ("sweet potato" over "potato").
        let candidates = table.keys
            .filter { IngredientMatcher.matches($0, key) }
            .sorted { $0.count > $1.count }
        if let best = candidates.first, let days = table[best] {
            return ShelfLifeEstimate(days: days, note: "Based on typical shelf life for \(best).", isConservative: true)
        }

        if let category, category != .other, let days = categoryDefaults[category] {
            return ShelfLifeEstimate(
                days: days,
                note: "Rough guess from the \(category.displayName.lowercased()) category.",
                isConservative: true
            )
        }

        return nil
    }

    /// Used as the absolute last resort if the network is unavailable.
    static func fallback(for category: FoodCategory) -> ShelfLifeEstimate {
        let days = categoryDefaults[category] ?? 14
        return ShelfLifeEstimate(
            days: days,
            note: "Offline guess from the \(category.displayName.lowercased()) category — please check.",
            isConservative: true
        )
    }
}
