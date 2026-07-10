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

        /// Builds a FoodItem from this AI estimate, except when a food
        /// preset already exists under the same name — then the preset's
        /// own saved nutrition numbers win over the AI's fresh guess for
        /// that food, since a value you've already saved (and presumably
        /// checked) is more trustworthy than a new estimate for something
        /// you've logged before. Grams (portion size) always comes from the
        /// AI, since a preset has no per-meal portion of its own.
        func makeFoodItem(presets: [FoodPreset], order: Int = 0) -> FoodItem {
            if let preset = FoodPresetSyncService.matchingPreset(named: name, in: presets) {
                return FoodItem(
                    name: preset.name,
                    grams: grams,
                    calories: preset.calories,
                    protein: preset.protein,
                    carbs: preset.carbs,
                    fat: preset.fat,
                    fiber: preset.fiber,
                    sodium: preset.sodium,
                    cookingMethod: preset.cookingMethod,
                    confidence: 1.0,
                    order: order
                )
            }
            return FoodItem(
                name: name,
                grams: grams,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                fiber: fiber,
                sodium: sodium,
                cookingMethod: CookingMethod(rawValue: cookingMethod.lowercased()) ?? .unknown,
                confidence: confidence,
                order: order
            )
        }
    }

    /// Build an unsaved MealLog draft from the estimate. Caller reviews/edits before inserting.
    /// `presets` lets any food item matching a saved preset by name use the
    /// preset's own numbers instead of the AI's estimate for that food (see
    /// `FoodItemEstimate.makeFoodItem`). Meal-level totals are the sum of
    /// the (possibly preset-substituted) items, same rule FoodItemEditorRow's
    /// onChanged uses everywhere else in the app, so a substitution shows up
    /// immediately instead of only after the user edits something.
    func makeDraft(date: Date = .now, photoPath: String? = nil, presets: [FoodPreset] = []) -> MealLog {
        let items = foodItems.enumerated().map { index, item in item.makeFoodItem(presets: presets, order: index) }
        let oil = items.isEmpty ? (low: hiddenOilLow, high: hiddenOilHigh) : HiddenOilEstimator.estimate(forFoodItems: items)
        let totalCalories = items.isEmpty ? estimatedCalories : items.reduce(0) { $0 + $1.calories }
        let meal = MealLog(
            date: date,
            mealType: MealType(rawValue: mealType) ?? .guess(for: date),
            photoPath: photoPath,
            calories: totalCalories,
            protein: items.isEmpty ? protein : items.reduce(0) { $0 + $1.protein },
            carbs: items.isEmpty ? carbs : items.reduce(0) { $0 + $1.carbs },
            fat: items.isEmpty ? fat : items.reduce(0) { $0 + $1.fat },
            fiber: items.isEmpty ? fiber : items.reduce(0) { $0 + $1.fiber },
            sodium: items.isEmpty ? sodium : items.reduce(0) { $0 + $1.sodium },
            confidence: confidence,
            calorieLow: items.isEmpty ? calorieLow : (totalCalories * 0.85).rounded(),
            calorieHigh: items.isEmpty ? calorieHigh : (totalCalories * 1.1 + oil.high).rounded(),
            hiddenOilLow: oil.low.rounded(),
            hiddenOilHigh: oil.high.rounded(),
            notes: notes,
            foodItems: items
        )
        return meal
    }
}
