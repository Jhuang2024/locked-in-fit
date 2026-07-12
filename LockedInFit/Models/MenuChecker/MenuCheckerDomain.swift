import Foundation

// MARK: - Nutrition source & confidence

/// Where a menu item's nutrition numbers come from. The UI must never present an
/// estimate as if it were official, so this distinction is first-class and is
/// surfaced on every card and detail screen.
enum NutritionSourceKind: String, Codable, CaseIterable, Identifiable {
    /// Published by the restaurant / brand as official nutrition facts.
    case official
    /// Restaurant listed the ingredients; macros derived from those.
    case restaurantProvided = "restaurant_provided"
    /// Estimated from dish description, likely ingredients, and portion size.
    case estimatedFromIngredients = "estimated_from_ingredients"
    /// Very little to go on — a rough guess flagged clearly to the user.
    case lowConfidenceEstimate = "low_confidence_estimate"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .official: return "Official nutrition"
        case .restaurantProvided: return "Restaurant-provided ingredients"
        case .estimatedFromIngredients: return "Estimated from ingredients"
        case .lowConfidenceEstimate: return "Low-confidence estimate"
        }
    }

    var shortLabel: String {
        switch self {
        case .official: return "Official"
        case .restaurantProvided: return "From ingredients"
        case .estimatedFromIngredients: return "Estimated"
        case .lowConfidenceEstimate: return "Rough estimate"
        }
    }

    /// True when the numbers came straight from the restaurant/brand and must
    /// not be adjusted by our own oil/portion estimators.
    var isOfficial: Bool { self == .official }

    var systemImage: String {
        switch self {
        case .official: return "checkmark.seal.fill"
        case .restaurantProvided: return "list.bullet.rectangle"
        case .estimatedFromIngredients: return "wand.and.stars"
        case .lowConfidenceEstimate: return "questionmark.circle"
        }
    }
}

/// Coarse confidence tier shown alongside every estimate. We never show fake
/// precision — confidence is high/medium/low, not a percentage.
enum NutritionConfidence: String, Codable, CaseIterable, Identifiable {
    case high, medium, low

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Maps to the 0–1 confidence field used by the existing MealLog model so
    /// menu-logged meals slot into the same confidence UI as everything else.
    var scalar: Double {
        switch self {
        case .high: return 0.85
        case .medium: return 0.6
        case .low: return 0.35
        }
    }

    init(scalar: Double) {
        switch scalar {
        case 0.75...: self = .high
        case 0.5..<0.75: self = .medium
        default: self = .low
        }
    }

    /// Lower of two confidences — combining components can only reduce certainty.
    static func min(_ a: NutritionConfidence, _ b: NutritionConfidence) -> NutritionConfidence {
        NutritionConfidence(scalar: Swift.min(a.scalar, b.scalar))
    }
}

// MARK: - Price, cuisine, dietary tags

enum PriceLevel: Int, Codable, CaseIterable, Identifiable, Comparable {
    case unknown = 0
    case budget = 1
    case moderate = 2
    case premium = 3
    case luxury = 4

    var id: Int { rawValue }
    static func < (lhs: PriceLevel, rhs: PriceLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// "$$$" style glyph. Unknown renders as an em dash.
    var glyphs: String { self == .unknown ? "—" : String(repeating: "$", count: rawValue) }
    var label: String {
        switch self {
        case .unknown: return "Price unknown"
        case .budget: return "Budget"
        case .moderate: return "Moderate"
        case .premium: return "Premium"
        case .luxury: return "Luxury"
        }
    }
}

/// Dietary properties an item can satisfy, used both for filtering restaurants /
/// items and for surfacing warnings against the user's restrictions.
enum DietaryTag: String, Codable, CaseIterable, Identifiable {
    case vegetarian, vegan
    case glutenFree = "gluten_free"
    case dairyFree = "dairy_free"
    case nutFree = "nut_free"
    case shellfishFree = "shellfish_free"
    case porkFree = "pork_free"
    case halal, kosher
    case lowSodium = "low_sodium"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .glutenFree: return "Gluten-free"
        case .dairyFree: return "Dairy-free"
        case .nutFree: return "Nut-free"
        case .shellfishFree: return "Shellfish-free"
        case .porkFree: return "Pork-free"
        case .halal: return "Halal"
        case .kosher: return "Kosher"
        case .lowSodium: return "Low sodium"
        }
    }
    var systemImage: String {
        switch self {
        case .vegetarian, .vegan: return "leaf.fill"
        case .glutenFree: return "g.circle"
        case .dairyFree: return "drop"
        case .nutFree: return "allergens"
        case .shellfishFree: return "fish"
        case .porkFree: return "nosign"
        case .halal, .kosher: return "checkmark.seal"
        case .lowSodium: return "minus.circle"
        }
    }
}

// MARK: - Geography

/// Plain lat/lon pair. Kept independent of CoreLocation so models stay testable
/// and Codable without importing CoreLocation everywhere.
struct GeoPoint: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres (haversine). Good enough for "1.2 km away".
    func distance(to other: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}

// MARK: - Resolved nutrition

/// A fully computed nutrition line for one serving of an item after
/// modifications, oil, and portion size are applied. This is the currency the
/// whole feature passes around — cards, cart totals, and meal logging all read
/// from it. Values here are *pre-rounding*; use `MenuValueRounding` for display.
struct ResolvedNutrition: Codable, Equatable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sodium: Double = 0
    /// Portion of `calories`/`fat` attributable to added oil, tracked separately
    /// so we never double-count it and can show the user the oil breakdown.
    var oilCalories: Double = 0
    var oilFatGrams: Double = 0

    static let zero = ResolvedNutrition()

    static func + (lhs: ResolvedNutrition, rhs: ResolvedNutrition) -> ResolvedNutrition {
        ResolvedNutrition(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat,
            fiber: lhs.fiber + rhs.fiber,
            sodium: lhs.sodium + rhs.sodium,
            oilCalories: lhs.oilCalories + rhs.oilCalories,
            oilFatGrams: lhs.oilFatGrams + rhs.oilFatGrams)
    }

    static func * (lhs: ResolvedNutrition, scale: Double) -> ResolvedNutrition {
        ResolvedNutrition(
            calories: lhs.calories * scale,
            protein: lhs.protein * scale,
            carbs: lhs.carbs * scale,
            fat: lhs.fat * scale,
            fiber: lhs.fiber * scale,
            sodium: lhs.sodium * scale,
            oilCalories: lhs.oilCalories * scale,
            oilFatGrams: lhs.oilFatGrams * scale)
    }
}

/// Central rounding policy so estimated items never show fake precision.
/// Calories to the nearest 5 (or 10 above 300), macros to the nearest gram.
enum MenuValueRounding {
    static func calories(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        let step: Double = value >= 300 ? 10 : 5
        return (value / step).rounded() * step
    }
    static func grams(_ value: Double) -> Double { value.rounded() }
    static func sodium(_ value: Double) -> Double { (value / 5).rounded() * 5 }

    /// Round an entire line for display. Only applied to estimates — official
    /// nutrition is shown exactly as provided.
    static func round(_ n: ResolvedNutrition, roundCalories: Bool = true) -> ResolvedNutrition {
        ResolvedNutrition(
            calories: roundCalories ? calories(n.calories) : n.calories,
            protein: grams(n.protein),
            carbs: grams(n.carbs),
            fat: grams(n.fat),
            fiber: grams(n.fiber),
            sodium: sodium(n.sodium),
            oilCalories: roundCalories ? calories(n.oilCalories) : n.oilCalories,
            oilFatGrams: grams(n.oilFatGrams))
    }
}
