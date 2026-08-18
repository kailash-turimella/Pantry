import Foundation

/// Measurement units we let the user pick from. Deliberately small — this is a
/// personal kitchen app, not a nutrition database.
enum MeasureUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case piece
    case gram
    case kilogram
    case milliliter
    case liter
    case ounce
    case pound
    case cup
    case tablespoon
    case teaspoon
    case pack
    case can
    case bunch
    case bottle

    var id: String { rawValue }

    /// Short form used in lists: "2 kg", "1 tbsp".
    var abbreviation: String {
        switch self {
        case .piece: return ""
        case .gram: return "g"
        case .kilogram: return "kg"
        case .milliliter: return "ml"
        case .liter: return "L"
        case .ounce: return "oz"
        case .pound: return "lb"
        case .cup: return "cup"
        case .tablespoon: return "tbsp"
        case .teaspoon: return "tsp"
        case .pack: return "pack"
        case .can: return "can"
        case .bunch: return "bunch"
        case .bottle: return "bottle"
        }
    }

    var displayName: String {
        switch self {
        case .piece: return "piece"
        default: return abbreviation
        }
    }

    /// Formats a quantity + unit the way a person would write it on a list.
    func format(_ quantity: Double) -> String {
        let number = Self.numberFormatter.string(from: NSNumber(value: quantity)) ?? "\(quantity)"
        guard !abbreviation.isEmpty else { return number }
        let needsPlural = quantity != 1 && Self.pluralizable.contains(self)
        return "\(number) \(abbreviation)\(needsPlural ? "s" : "")"
    }

    private static let pluralizable: Set<MeasureUnit> = [.cup, .tablespoon, .teaspoon, .pack, .can, .bunch, .bottle]

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    /// Best-effort mapping of whatever string Claude (or a pasted recipe) hands us.
    static func parse(_ raw: String?) -> MeasureUnit {
        guard let raw, !raw.isEmpty else { return .piece }
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch key {
        case "g", "gram", "grams", "gr": return .gram
        case "kg", "kilo", "kilos", "kilogram", "kilograms": return .kilogram
        case "ml", "milliliter", "millilitre", "milliliters", "millilitres": return .milliliter
        case "l", "liter", "litre", "liters", "litres": return .liter
        case "oz", "ounce", "ounces": return .ounce
        case "lb", "lbs", "pound", "pounds": return .pound
        case "cup", "cups", "c": return .cup
        case "tbsp", "tablespoon", "tablespoons", "tbs", "tb": return .tablespoon
        case "tsp", "teaspoon", "teaspoons", "ts": return .teaspoon
        case "pack", "packs", "package", "packages", "packet", "packets", "box", "boxes": return .pack
        case "can", "cans", "tin", "tins": return .can
        case "bunch", "bunches": return .bunch
        case "bottle", "bottles", "jar", "jars": return .bottle
        default: return .piece
        }
    }
}
