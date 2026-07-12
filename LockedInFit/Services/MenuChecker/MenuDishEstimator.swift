import Foundation

/// Estimates a single described dish for a specific restaurant using the AI
/// gateway (OpenRouter → BazaarLink). The restaurant name + cuisine are folded
/// into the prompt so the model guesses a realistic restaurant-sized portion;
/// the returned calories/macros are turned into a `MenuItem` so the normal
/// resolver produces the Health and Satiety scores. Nothing here is "official" —
/// it's an estimate, tagged as such.
enum MenuDishEstimator {

    static func estimate(restaurant: Restaurant, description: String, settings: UserSettings?) async throws -> MenuItem {
        let service = AIServiceFactory.make(settings: settings)
        let cuisine = restaurant.cuisines.isEmpty ? "" : " (\(restaurant.primaryCuisine) cuisine)"
        // Give the model the restaurant context inline so it sizes and styles the
        // estimate like a real menu portion from that place.
        let prompt = "\(description) — a menu item from the restaurant \"\(restaurant.name)\"\(cuisine). Estimate a typical restaurant-sized portion as served there."
        let context = MealAnalysisContext(mealType: .guess(), userDescription: restaurant.name, isLikelyHomeCooked: false)
        let estimate = try await service.analyzeMeal(description: prompt, context: context)
        return makeItem(restaurant: restaurant, description: description, estimate: estimate)
    }

    /// Fold the AI estimate into a MenuItem. Hidden-oil uncertainty is folded
    /// into the totals (matching how the app treats a described meal), and the
    /// oil default is `.none` so the resolver doesn't add oil a second time.
    static func makeItem(restaurant: Restaurant, description: String, estimate: MealEstimate) -> MenuItem {
        let hiddenOilMid = (estimate.hiddenOilLow + estimate.hiddenOilHigh) / 2
        let totalCalories = estimate.estimatedCalories + hiddenOilMid
        let totalFat = estimate.fat + hiddenOilMid / MenuOilEstimator.kcalPerGramOil

        let name = dishName(from: description, estimate: estimate)
        let itemID = restaurant.id + ":described:" + SampleMenuData.slug(name) + "-\(Int(estimate.estimatedCalories))"
        let grams = max(50, estimate.foodItems.reduce(0) { $0 + $1.grams })

        let base = ResolvedNutrition(
            calories: totalCalories,
            protein: estimate.protein,
            carbs: estimate.carbs,
            fat: totalFat,
            fiber: estimate.fiber,
            sodium: estimate.sodium)

        let component = MenuItemComponent(
            id: itemID + "#0",
            name: name,
            kind: .main,
            grams: grams > 0 ? grams : totalCalories / 1.8,
            base: base,
            cookingMethod: .unknown,
            removable: false)

        let confidence = NutritionConfidence(scalar: estimate.confidence)
        return MenuItem(
            id: itemID,
            restaurantID: restaurant.id,
            name: name,
            itemDescription: "You described this · estimated for \(restaurant.name)",
            category: .mains,
            currencyCode: restaurant.currencyCode,
            components: [component],
            modifications: MenuModificationFactory.standard(for: [component]),
            defaultOilLevel: .none,
            sourceKind: confidence == .low ? .lowConfidenceEstimate : .estimatedFromIngredients,
            baseConfidence: confidence,
            servingBasis: .perItem)
    }

    private static func dishName(from description: String, estimate: MealEstimate) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // Use a short version of what the user typed as the item name.
            let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
            return String(firstLine.prefix(60))
        }
        return estimate.foodItems.first?.name ?? "Described dish"
    }
}
