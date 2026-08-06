import Foundation

/// Estimates hidden-oil calorie uncertainty by cooking method and food type.
/// Values are extra kcal that may be present beyond the visible estimate.
///
/// ## Absolute rule
/// Raw, steamed, boiled, and poached food gets exactly **0** hidden oil: no
/// range, no "a restaurant might have". An apple is an apple. This is the same
/// rule `MenuOilEstimator` already enforces for Menu Checker dishes, and it
/// applies here before any food-name modifier, so a *boiled* rice noodle isn't
/// handed the oil budget of a stir-fried one just because of its name. Oil
/// enters a dish like this only through a separately logged oily sauce,
/// dressing, or topping, which is its own food item with its own estimate.
enum HiddenOilEstimator {

    /// Cooking methods that add no oil to the food, ever.
    static let zeroOilMethods: Set<CookingMethod> = [.raw, .steamed, .boiled, .poached]

    /// Per-item hidden oil range in kcal, scaled by portion size.
    static func range(for name: String, method: CookingMethod, grams: Double) -> (low: Double, high: Double) {
        let lowered = name.lowercased()
        // An unstated method that the food's own name answers ("steamed corn",
        // "boiled rice noodles") is that method, not a mystery: reuse the same
        // parser Menu Checker and speech dictation resolve prep words with,
        // rather than charging the food the unknown-prep oil assumption.
        let method = method == .unknown ? (CookingMethod.detect(in: lowered) ?? .unknown) : method
        guard !zeroOilMethods.contains(method) else { return (0, 0) }
        // Base risk per ~150 g portion by cooking method.
        var base: (Double, Double)
        switch method {
        case .raw, .steamed, .boiled, .poached:
            base = (0, 0) // unreachable: handled by the guard above
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

    /// How a meal's hidden oil actually lands in the day's numbers: the counted
    /// figure first, the range second as the uncertainty around it. The
    /// midpoint is the number that matters — it's what `hiddenOilCalories`
    /// adds to consumed calories and subtracts from the day's remaining target
    /// — so showing only the range left the one figure that's actually applied
    /// nowhere on screen. Returns nil when there's no oil to report.
    static func countedLabel(low: Double, high: Double) -> String? {
        guard high > 0 else { return nil }
        let counted = Int((((low + high) / 2)).rounded())
        return "Oil +\(counted) kcal counted (range \(Int(low.rounded()))–\(Int(high.rounded())))"
    }

    static func riskLabel(for method: CookingMethod) -> String {
        switch method {
        case .steamed, .boiled, .poached, .raw: return "No added oil"
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
