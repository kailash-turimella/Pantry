import SwiftUI

/// Coarse grouping used for list sections, icons, and as a hint to the
/// shelf-life estimator.
enum FoodCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case produce
    case dairy
    case meat
    case seafood
    case bakery
    case pantry
    case frozen
    case beverage
    case condiment
    case leftovers
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .produce: return "Produce"
        case .dairy: return "Dairy & Eggs"
        case .meat: return "Meat"
        case .seafood: return "Seafood"
        case .bakery: return "Bakery"
        case .pantry: return "Pantry"
        case .frozen: return "Frozen"
        case .beverage: return "Drinks"
        case .condiment: return "Condiments"
        case .leftovers: return "Leftovers"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .produce: return "carrot.fill"
        case .dairy: return "drop.fill"
        case .meat: return "fork.knife"
        case .seafood: return "fish.fill"
        case .bakery: return "birthday.cake.fill"
        case .pantry: return "shippingbox.fill"
        case .frozen: return "snowflake"
        case .beverage: return "cup.and.saucer.fill"
        case .condiment: return "waterbottle.fill"
        case .leftovers: return "takeoutbag.and.cup.and.straw.fill"
        case .other: return "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .produce: return .green
        case .dairy: return .blue
        case .meat: return .red
        case .seafood: return .teal
        case .bakery: return .brown
        case .pantry: return .orange
        case .frozen: return .cyan
        case .beverage: return .purple
        case .condiment: return .yellow
        case .leftovers: return .pink
        case .other: return .gray
        }
    }

    static func parse(_ raw: String?) -> FoodCategory {
        guard let raw else { return .other }
        return FoodCategory(rawValue: raw.lowercased().trimmingCharacters(in: .whitespaces)) ?? .other
    }
}
