import Foundation

/// An AI-estimated described dish, ready for the user to review and correct
/// before adding to the cart. Editable, so the numbers aren't presented as gospel.
struct EstimatedDish: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var nutrition: ResolvedNutrition
    var confidence: NutritionConfidence
}

/// Estimates a single described dish for a specific restaurant using the AI
/// gateway (OpenRouter → BazaarLink). The restaurant name + cuisine are folded
/// into the prompt so the model guesses a realistic restaurant-sized portion.
/// Returns editable calories/macros — nothing here is "official".
enum MenuDishEstimator {

    static func estimate(restaurant: Restaurant, description: String, settings: UserSettings?) async throws -> EstimatedDish {
        let service = AIServiceFactory.make(settings: settings)
        let cuisine = restaurant.cuisines.isEmpty ? "" : " (\(restaurant.primaryCuisine) cuisine)"
        let prompt = "\(description) — a menu item from the restaurant \"\(restaurant.name)\"\(cuisine). Estimate a typical restaurant-sized portion as served there."
        let context = MealAnalysisContext(mealType: .guess(), userDescription: restaurant.name, isLikelyHomeCooked: false)
        let estimate = try await service.analyzeMeal(description: prompt, context: context)

        // Fold hidden-oil uncertainty into the totals (matching how the app
        // treats a described meal), so the single number the user sees is honest.
        let hiddenOilMid = (estimate.hiddenOilLow + estimate.hiddenOilHigh) / 2
        let nutrition = ResolvedNutrition(
            calories: (estimate.estimatedCalories + hiddenOilMid).rounded(),
            protein: estimate.protein.rounded(),
            carbs: estimate.carbs.rounded(),
            fat: (estimate.fat + hiddenOilMid / MenuOilEstimator.kcalPerGramOil).rounded(),
            fiber: estimate.fiber.rounded(),
            sodium: estimate.sodium.rounded())

        return EstimatedDish(
            name: dishName(from: description, estimate: estimate),
            nutrition: nutrition,
            confidence: NutritionConfidence(scalar: estimate.confidence))
    }

    private static func dishName(from description: String, estimate: MealEstimate) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
            return String(firstLine.prefix(60))
        }
        return estimate.foodItems.first?.name ?? "Described dish"
    }
}
