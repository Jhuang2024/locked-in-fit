import Foundation

/// Estimated added cooking oil for a single food component.
struct OilEstimate: Equatable {
    var grams: Double
    var calories: Double
    var detail: String

    static let zero = OilEstimate(grams: 0, calories: 0, detail: "No added oil")
    var isZero: Bool { grams == 0 && calories == 0 }
}

/// The Menu Checker oil model. Estimates *added cooking oil* only — never the
/// fat already inside sauces, dressings, cheese, or the food itself (those carry
/// their own macros). This is the single source of truth for oil across Menu
/// Checker and speech meal dictation.
///
/// ## Absolute rule
/// Anything identified as **steamed** or **raw** receives exactly **0** oil
/// calories and **0** grams of added oil fat — no range, no "restaurants might".
/// Oil only enters such a dish through a separately listed oily sauce, dressing,
/// marinade, or topping, which is a different component and estimated on its own.
enum MenuOilEstimator {

    /// Energy density of cooking oil. Fat is 9 kcal/g; culinary oil is ~8.84,
    /// but we use 9 so oil calories and the fat macro stay internally consistent.
    static let kcalPerGramOil: Double = 9

    /// Standard added-oil grams per 100 g of food, before the oil-level
    /// multiplier. These are *retained* oil estimates (what ends up in the food),
    /// not the total oil that hit the pan.
    static func standardGramsPer100g(for method: CookingMethod, foodName: String) -> Double {
        let l = foodName.lowercased()
        switch method {
        case .steamed, .raw:
            return 0 // absolute rule — enforced again in `estimate` as a guard
        case .boiled, .poached:
            return 0 // default zero unless an oily component is listed separately
        case .soup:
            return 0.6 // broth fat, small
        case .grilled:
            // Never auto-zero: marinade / finishing oil or butter.
            return 1.4
        case .roasted:
            return 2.6
        case .baked:
            // Depends on the recipe: pastry/gratin carry fat, a plain bake little.
            if l.contains("pastry") || l.contains("croissant") || l.contains("gratin") || l.contains("cheese") { return 4.0 }
            return 1.6
        case .sauteed:
            return 2.6 // retained, not all oil added to the pan
        case .panFried:
            return 3.6
        case .braised:
            return 3.0
        case .stirFried:
            return 4.2
        case .deepFried:
            return deepFryGramsPer100g(foodName: l)
        case .restaurantHighOil:
            return 5.0
        case .unknown:
            return 2.0 // assume some oil rather than pretend there's none
        }
    }

    /// Deep-frying absorption depends on food type, breading, and surface area.
    /// Battered/breaded and high-surface-area foods (fries, small pieces) soak up
    /// substantially more oil than a dense fillet.
    private static func deepFryGramsPer100g(foodName l: String) -> Double {
        var g = 7.0
        let breaded = l.contains("breaded") || l.contains("crispy") || l.contains("batter")
            || l.contains("tempura") || l.contains("katsu") || l.contains("nugget")
            || l.contains("schnitzel") || l.contains("popcorn")
        if breaded { g += 3.0 }
        if l.contains("fries") || l.contains("chips") || l.contains("fry") || l.contains("crisp") {
            g = max(g, 13.0) // high surface area, very absorbent
        }
        if l.contains("spring roll") || l.contains("wonton") || l.contains("dumpling") { g = max(g, 11.0) }
        if l.contains("donut") || l.contains("doughnut") || l.contains("churro") { g = max(g, 12.0) }
        return g
    }

    /// Estimate added oil for one component.
    ///
    /// - Parameters:
    ///   - foodName: item/component name, used for food-specific absorption.
    ///   - method: cooking method — the absolute rule keys off `.steamed` / `.raw`.
    ///   - grams: portion weight of the component.
    ///   - level: user-facing oil assumption (none/light/standard/heavy/custom).
    ///   - customGrams: explicit oil grams when `level == .custom`.
    ///   - carriesOwnFat: true for sauces/dressings/cheese — such components must
    ///     not receive additional cooking oil (their fat is already counted).
    static func estimate(foodName: String,
                         method: CookingMethod,
                         grams: Double,
                         level: OilLevel = .standard,
                         customGrams: Double? = nil,
                         carriesOwnFat: Bool = false) -> OilEstimate {
        // Absolute rule, enforced first and unconditionally: steamed or raw food
        // gets exactly zero added oil. Nothing below can override this.
        if method == .steamed || method == .raw {
            let detail = "\(method.label): zero added oil (absolute rule)"
            return OilEstimate(grams: 0, calories: 0, detail: detail)
        }

        // Components that already include their own fat (sauces, cheese…) never
        // get cooking oil piled on top — that would double-count.
        if carriesOwnFat {
            return OilEstimate(grams: 0, calories: 0, detail: "Fat already counted in this component")
        }

        // Explicit custom amount short-circuits the method model.
        if level == .custom, let custom = customGrams {
            let g = max(0, custom)
            return OilEstimate(grams: g, calories: g * kcalPerGramOil,
                               detail: "Custom oil: \(Int(g.rounded())) g")
        }

        // "None" is an explicit user choice of zero for methods that otherwise
        // assume oil.
        if level == .none {
            return OilEstimate(grams: 0, calories: 0, detail: "Oil set to none")
        }

        let base = standardGramsPer100g(for: method, foodName: foodName)
        guard base > 0, grams > 0 else {
            return OilEstimate(grams: 0, calories: 0,
                               detail: "\(method.label): no added cooking oil expected")
        }
        let grams100 = grams / 100
        let oilGrams = base * grams100 * level.multiplier
        let cals = oilGrams * kcalPerGramOil
        let detail = "\(method.label) (\(level.label.lowercased()) oil): ~\(Int(oilGrams.rounded())) g oil"
        return OilEstimate(grams: oilGrams, calories: cals, detail: detail)
    }
}
