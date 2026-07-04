import Foundation

/// Strict JSON contract returned by the AI (or mock) meal analyzer.
struct MealEstimate: Codable {
    var mealType: String
    var estimatedCalories: Double
    var calorieLow: Double
    var calorieHigh: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var sodium: Double
    var confidence: Double
    var hiddenOilLow: Double
    var hiddenOilHigh: Double
    var notes: String
    var foodItems: [FoodItemEstimate]

    struct FoodItemEstimate: Codable {
        var name: String
        var grams: Double
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var fiber: Double
        var sodium: Double
        var cookingMethod: String
        var confidence: Double
    }

    /// Build an unsaved MealLog draft from the estimate. Caller reviews/edits before inserting.
    func makeDraft(date: Date = .now, photoPath: String? = nil) -> MealLog {
        let meal = MealLog(
            date: date,
            mealType: MealType(rawValue: mealType) ?? .guess(for: date),
            photoPath: photoPath,
            calories: estimatedCalories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sodium: sodium,
            confidence: confidence,
            calorieLow: calorieLow,
            calorieHigh: calorieHigh,
            hiddenOilLow: hiddenOilLow,
            hiddenOilHigh: hiddenOilHigh,
            notes: notes,
            foodItems: foodItems.map {
                FoodItem(
                    name: $0.name,
                    grams: $0.grams,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat,
                    fiber: $0.fiber,
                    sodium: $0.sodium,
                    cookingMethod: CookingMethod(rawValue: $0.cookingMethod.lowercased()) ?? .unknown,
                    confidence: $0.confidence
                )
            }
        )
        return meal
    }
}
