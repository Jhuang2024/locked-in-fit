import Foundation
import UIKit

/// Offline mock analyzer. Produces realistic estimates, biased toward
/// home-cooked meals with honest hidden-oil uncertainty.
struct MockFoodAIService: FoodAIService {
    let providerName = "Mock (offline)"

    private struct Template {
        let notes: String
        let items: [MealEstimate.FoodItemEstimate]
    }

    private static let templates: [Template] = [
        Template(
            notes: "Estimate includes likely stir-fry oil. Home-cooked dishes vary widely in oil.",
            items: [
                .init(name: "stir-fried eggplant", grams: 180, calories: 260, protein: 4, carbs: 22, fat: 18, fiber: 6, sodium: 480, cookingMethod: "stir-fried", confidence: 0.6),
                .init(name: "steamed white rice", grams: 200, calories: 260, protein: 5, carbs: 57, fat: 1, fiber: 1, sodium: 5, cookingMethod: "steamed", confidence: 0.85),
                .init(name: "stir-fried pork slices", grams: 100, calories: 230, protein: 18, carbs: 3, fat: 16, fiber: 0, sodium: 420, cookingMethod: "stir-fried", confidence: 0.55)
            ]),
        Template(
            notes: "Soup keeps oil moderate; watch the surface fat layer on duck soup.",
            items: [
                .init(name: "winter melon soup", grams: 300, calories: 90, protein: 4, carbs: 8, fat: 5, fiber: 2, sodium: 620, cookingMethod: "soup", confidence: 0.7),
                .init(name: "boiled dumplings (pork & chive)", grams: 220, calories: 420, protein: 18, carbs: 52, fat: 15, fiber: 3, sodium: 780, cookingMethod: "boiled", confidence: 0.65),
                .init(name: "marinated cucumber", grams: 80, calories: 45, protein: 1, carbs: 5, fat: 2.5, fiber: 1, sodium: 340, cookingMethod: "raw", confidence: 0.8)
            ]),
        Template(
            notes: "Lean protein plate. Low oil risk; grilled surfaces may carry a little.",
            items: [
                .init(name: "grilled chicken breast", grams: 160, calories: 265, protein: 49, carbs: 0, fat: 6, fiber: 0, sodium: 380, cookingMethod: "grilled", confidence: 0.8),
                .init(name: "baked potato", grams: 200, calories: 190, protein: 4, carbs: 43, fat: 0.3, fiber: 4, sodium: 15, cookingMethod: "baked", confidence: 0.85),
                .init(name: "steamed broccoli", grams: 120, calories: 40, protein: 3, carbs: 8, fat: 0.5, fiber: 3, sodium: 30, cookingMethod: "steamed", confidence: 0.85)
            ]),
        Template(
            notes: "Noodle dishes absorb sauce oil; range widened accordingly.",
            items: [
                .init(name: "stir-fried noodles with beef", grams: 320, calories: 560, protein: 26, carbs: 62, fat: 22, fiber: 4, sodium: 1150, cookingMethod: "stir-fried", confidence: 0.55),
                .init(name: "stir-fried leafy greens (garlic)", grams: 150, calories: 110, protein: 3, carbs: 6, fat: 9, fiber: 3, sodium: 350, cookingMethod: "stir-fried", confidence: 0.6)
            ]),
        Template(
            notes: "Tofu and black fungus carry moderate oil from the wok.",
            items: [
                .init(name: "braised tofu", grams: 180, calories: 220, protein: 16, carbs: 8, fat: 14, fiber: 2, sodium: 560, cookingMethod: "braised", confidence: 0.6),
                .init(name: "black fungus salad", grams: 90, calories: 70, protein: 2, carbs: 8, fat: 4, fiber: 3, sodium: 410, cookingMethod: "raw", confidence: 0.7),
                .init(name: "steamed white rice", grams: 180, calories: 235, protein: 4, carbs: 51, fat: 0.5, fiber: 1, sodium: 4, cookingMethod: "steamed", confidence: 0.85),
                .init(name: "boiled shrimp", grams: 100, calories: 100, protein: 22, carbs: 0.5, fat: 1, fiber: 0, sodium: 300, cookingMethod: "boiled", confidence: 0.75)
            ])
    ]

    func analyzeMeal(image: UIImage, context: MealAnalysisContext) async throws -> MealEstimate {
        // Simulate a short analysis delay so the UI flow matches the real provider.
        try await Task.sleep(for: .seconds(1.2))

        var template = Self.templates.randomElement()!
        // Small random scaling so repeated mock runs don't look identical.
        let scale = Double.random(in: 0.85...1.15)
        let items = template.items.map { item in
            var i = item
            i.grams = (i.grams * scale).rounded()
            i.calories = (i.calories * scale).rounded()
            i.protein = (i.protein * scale).rounded()
            i.carbs = (i.carbs * scale).rounded()
            i.fat = (i.fat * scale).rounded()
            i.fiber = (i.fiber * scale).rounded()
            i.sodium = (i.sodium * scale).rounded()
            return i
        }
        template = Template(notes: template.notes, items: items)

        let calories = items.reduce(0) { $0 + $1.calories }
        let oil = HiddenOilEstimator.estimate(for: items)
        let avgConfidence = items.map(\.confidence).reduce(0, +) / Double(items.count)

        return MealEstimate(
            mealType: context.mealType.rawValue,
            estimatedCalories: calories.rounded(),
            calorieLow: (calories * 0.85).rounded(),
            calorieHigh: (calories * 1.1 + oil.high).rounded(),
            protein: items.reduce(0) { $0 + $1.protein },
            carbs: items.reduce(0) { $0 + $1.carbs },
            fat: items.reduce(0) { $0 + $1.fat },
            fiber: items.reduce(0) { $0 + $1.fiber },
            sodium: items.reduce(0) { $0 + $1.sodium },
            confidence: (avgConfidence * 100).rounded() / 100,
            hiddenOilLow: oil.low.rounded(),
            hiddenOilHigh: oil.high.rounded(),
            notes: "[Mock estimate] " + template.notes,
            foodItems: items
        )
    }

    func testConnection() async throws -> String {
        "Mock mode is always available — no network needed."
    }
}
