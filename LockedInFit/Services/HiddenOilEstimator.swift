import Foundation

/// Estimates hidden-oil calorie uncertainty by cooking method and food type.
/// Values are extra kcal that may be present beyond the visible estimate.
enum HiddenOilEstimator {

    /// Per-item hidden oil range in kcal, scaled by portion size.
    static func range(for name: String, method: CookingMethod, grams: Double) -> (low: Double, high: Double) {
        let lowered = name.lowercased()
        // Base risk per ~150 g portion by cooking method.
        var base: (Double, Double)
        switch method {
        case .steamed, .boiled, .raw:
            base = (0, 15)
        case .soup:
            base = (5, 40)
        case .grilled, .baked:
            base = (10, 60)
        case .braised:
            base = (25, 100)
        case .stirFried:
            base = (40, 130)
        case .deepFried:
            base = (80, 200)
        case .restaurantHighOil:
            base = (60, 180)
        case .unknown:
            base = (20, 100)
        }
        // Food-specific modifiers.
        if lowered.contains("eggplant") {
            base = (max(base.0, 60), max(base.1, 200)) // eggplant is an oil sponge
        }
        if lowered.contains("noodle") || lowered.contains("rice") && lowered.contains("sauce") || lowered.contains("fried rice") {
            base = (max(base.0, 35), max(base.1, 120))
        }
        if lowered.contains("tofu") {
            base = (max(base.0, 20), max(base.1, 90))
        }
        if method == .unknown, lowered.contains("pork") || lowered.contains("beef") || lowered.contains("lamb") || lowered.contains("duck") {
            base = (max(base.0, 40), max(base.1, 150)) // unknown meat prep: assume oil/fat
        }
        let portionScale = max(0.4, min(2.5, grams / 150))
        return (base.0 * portionScale, base.1 * portionScale)
    }

    static func estimate(for items: [MealEstimate.FoodItemEstimate]) -> (low: Double, high: Double) {
        items.reduce((0.0, 0.0)) { acc, item in
            let method = CookingMethod(rawValue: item.cookingMethod.lowercased()) ?? .unknown
            let r = range(for: item.name, method: method, grams: item.grams)
            return (acc.0 + r.low, acc.1 + r.high)
        }
    }

    static func estimate(forFoodItems items: [FoodItem]) -> (low: Double, high: Double) {
        items.reduce((0.0, 0.0)) { acc, item in
            let r = range(for: item.name, method: item.cookingMethod, grams: item.grams)
            return (acc.0 + r.low, acc.1 + r.high)
        }
    }

    static func riskLabel(for method: CookingMethod) -> String {
        switch method {
        case .steamed, .boiled, .raw: return "Low oil risk"
        case .soup: return "Low–medium oil risk"
        case .grilled, .baked: return "Medium oil risk"
        case .braised: return "Medium–high oil risk"
        case .stirFried: return "Medium–high oil risk"
        case .deepFried: return "Very high oil risk"
        case .restaurantHighOil: return "High oil risk"
        case .unknown: return "Unknown — assume oil"
        }
    }
}
