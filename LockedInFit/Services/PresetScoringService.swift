import Foundation

/// Health/Satiety scores for saved food presets, computed with the exact same
/// calculators Menu Checker uses (MenuHealthScoreCalculator /
/// SatietyScoreCalculator), so a preset and a menu item with the same macros
/// always score identically instead of the two features quietly disagreeing.
enum PresetScoringService {
    struct Scores: Equatable {
        var health: Double
        var satiety: Double
    }

    /// Both calculators lean on calorie density (kcal per gram), which needs a
    /// weight. When a preset has no usable reference weight, assume this
    /// neutral density to derive one: 2.0 kcal/g sits in the dead zone of both
    /// calculators' density rules, so an unknown weight neither earns a
    /// "great food volume" bonus nor a "calorie-dense" penalty it didn't prove.
    static let neutralCaloriesPerGram = 2.0

    static func scores(for preset: FoodPreset, profile: ScoringProfile = .neutral) -> Scores {
        let nutrition = ResolvedNutrition(
            calories: preset.calories,
            protein: preset.protein,
            carbs: preset.carbs,
            fat: preset.fat,
            fiber: preset.fiber,
            sodium: preset.sodium)
        let grams = preset.effectiveReferenceGrams > 0
            ? preset.effectiveReferenceGrams
            : max(1, preset.calories / neutralCaloriesPerGram)
        // One synthetic "main" component carrying the preset's macros and
        // cooking method: enough for the density/protein/fibre/sodium signals,
        // and the deep-fried penalty still applies through the method.
        let component = MenuItemComponent(
            name: preset.name,
            kind: .main,
            grams: grams,
            base: nutrition,
            cookingMethod: preset.cookingMethod)
        let health = MenuHealthScoreCalculator.score(
            nutrition: nutrition, components: [component],
            sourceKind: .estimatedFromIngredients, profile: profile).score
        let satiety = SatietyScoreCalculator.score(
            nutrition: nutrition, components: [component], profile: profile).score
        return Scores(health: health, satiety: satiety)
    }
}
