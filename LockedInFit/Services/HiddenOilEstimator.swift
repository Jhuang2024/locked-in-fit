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
        case .steamed, .boiled, .poached, .raw:
            base = (0, 8)
        case .soup:
            base = (0, 25)
        case .grilled, .baked, .roasted:
            base = (5, 35)
        case .sauteed:
            base = (18, 65)
        case .braised:
            base = (20, 75)
        case .panFried:
            base = (28, 85)
        case .stirFried:
            base = (30, 95)
        case .deepFried:
            base = (70, 160)
        case .restaurantHighOil:
            base = (45, 140)
        case .unknown:
            base = (10, 65)
        }
        // Food-specific modifiers.
        if lowered.contains("eggplant") {
            base = (max(base.0, 45), max(base.1, 145)) // eggplant is an oil sponge
        }
        if lowered.contains("noodle") || lowered.contains("rice") && lowered.contains("sauce") || lowered.contains("fried rice") {
            base = (max(base.0, 25), max(base.1, 90))
        }
        if lowered.contains("tofu") {
            base = (max(base.0, 15), max(base.1, 65))
        }
        if method == .unknown, lowered.contains("pork") || lowered.contains("beef") || lowered.contains("lamb") || lowered.contains("duck") {
            base = (max(base.0, 25), max(base.1, 100)) // unknown meat prep: assume oil/fat
        }
        let portionScale = max(0.5, min(2.0, grams / 150))
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
        case .steamed, .boiled, .poached, .raw: return "Low oil risk"
        case .soup: return "Low–medium oil risk"
        case .grilled, .baked, .roasted: return "Medium oil risk"
        case .sauteed: return "Medium–high oil risk"
        case .braised: return "Medium–high oil risk"
        case .panFried: return "Medium–high oil risk"
        case .stirFried: return "Medium–high oil risk"
        case .deepFried: return "Very high oil risk"
        case .restaurantHighOil: return "High oil risk"
        case .unknown: return "Unknown, assume oil"
        }
    }
}
