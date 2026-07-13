import Foundation

/// Builds structured `MenuItemComponent`s (and derived dietary/confidence info)
/// from a dish name + description. This is the reusable estimation core used
/// both to synthesize menu items when a restaurant publishes no nutrition and to
/// turn a spoken/typed meal into components. Oil is NOT baked into the component
/// macros here; it's applied at resolve time by `MenuOilEstimator`, so changing
/// the oil assumption later recalculates cleanly and never double-counts.
enum MenuNutritionEstimator {

    struct Result {
        var components: [MenuItemComponent]
        var sourceKind: NutritionSourceKind
        var confidence: NutritionConfidence
        var dietaryTags: [DietaryTag]
        var uncertainTerms: [String]
        var defaultOilLevel: OilLevel
    }

    /// Estimate components for a dish. When nothing recognizable is found, a
    /// single generic component is returned and the result is flagged
    /// low-confidence; we never pretend a blind guess is precise.
    static func estimate(name: String, description: String = "", portionScale: Double = 1) -> Result {
        let parsed = IngredientParser.parse(name: name, description: description)

        var components: [MenuItemComponent] = []
        for pc in parsed.components {
            let grams = pc.grams * parsed.portionMultiplier * portionScale
            let base = pc.profile.per100g * (grams / 100)
            components.append(MenuItemComponent(
                name: pc.profile.canonicalName,
                kind: pc.profile.kind,
                grams: grams,
                base: base,
                cookingMethod: pc.method,
                removable: pc.profile.kind != .main))
        }

        var confidence = parsed.confidence
        var source: NutritionSourceKind = .estimatedFromIngredients

        if components.isEmpty {
            components = [fallbackComponent(name: name, portionScale: portionScale)]
            confidence = .low
            source = .lowConfidenceEstimate
        }

        let defaultOil = parsed.oilLevel ?? inferOilLevel(components: components)
        let dietary = dietaryTags(for: components)

        return Result(components: components,
                      sourceKind: source,
                      confidence: confidence,
                      dietaryTags: dietary,
                      uncertainTerms: parsed.uncertainTerms,
                      defaultOilLevel: defaultOil)
    }

    /// A generic restaurant-plate estimate for a dish we couldn't parse.
    private static func fallbackComponent(name: String, portionScale: Double) -> MenuItemComponent {
        let grams = 350 * portionScale
        // Middle-of-the-road restaurant main: moderate protein, mixed carbs/fat.
        let per100 = ResolvedNutrition(calories: 180, protein: 8, carbs: 18, fat: 8, fiber: 2, sodium: 220)
        return MenuItemComponent(
            name: name.isEmpty ? "Estimated dish" : name,
            kind: .main,
            grams: grams,
            base: per100 * (grams / 100),
            cookingMethod: CookingMethod.detect(in: name) ?? .unknown,
            removable: false)
    }

    /// Pick a sensible default oil level from the components' cooking methods.
    private static func inferOilLevel(components: [MenuItemComponent]) -> OilLevel {
        let methods = components.map(\.cookingMethod)
        if methods.allSatisfy({ $0 == .steamed || $0 == .raw || $0 == .boiled || $0 == .poached }) {
            return OilLevel.none
        }
        if methods.contains(.deepFried) || methods.contains(.restaurantHighOil) { return .standard }
        return .standard
    }

    /// An item is vegan only if every component is vegan; vegetarian only if
    /// every component is at least vegetarian. Other tags pass through when all
    /// components share them.
    static func dietaryTags(for components: [MenuItemComponent], hints: [FoodProfile] = []) -> [DietaryTag] {
        // We infer from component names against the table since components don't
        // carry tags directly.
        let profilesByName = Dictionary(FoodNutritionTable.all.map { ($0.canonicalName, $0) }, uniquingKeysWith: { a, _ in a })
        var allVegan = true
        var allVegetarian = true
        for c in components {
            let tags = profilesByName[c.name]?.dietaryTags ?? []
            if !tags.contains(.vegan) { allVegan = false }
            if !(tags.contains(.vegan) || tags.contains(.vegetarian)) { allVegetarian = false }
        }
        var result: [DietaryTag] = []
        if allVegan { result.append(.vegan) }
        if allVegan || allVegetarian { result.append(.vegetarian) }
        return result
    }
}
