import Foundation

/// Snapshot of an already-logged meal's nutrition, handed to the AI for
/// health/satiety scoring. Built straight from the saved MealLog, so scoring
/// works identically whether the meal came from a photo estimate, a typed
/// description, a preset, or fully manual entry — by the time this runs, the
/// calories/macros are already final.
struct MealNutritionAnalysisInput {
    var mealType: MealType
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var sodium: Double
    var itemNames: [String]
    var notes: String

    init(meal: MealLog) {
        mealType = meal.mealType
        calories = meal.calories
        protein = meal.protein
        carbs = meal.carbs
        fat = meal.fat
        fiber = meal.fiber
        sodium = meal.sodium
        itemNames = meal.items.map(\.name)
        notes = meal.notes
    }
}

/// Modular meal health/satiety scoring provider. Swap implementations via
/// AIServiceFactory, same as calorie estimation and health-scan analysis.
protocol MealNutritionAIService {
    var providerName: String { get }
    func analyze(_ input: MealNutritionAnalysisInput) async throws -> MealNutritionEstimate
}
