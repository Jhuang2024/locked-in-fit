import Foundation

/// Offline heuristic scorer: no network, no AI — just macro-density math plus
/// a few keyword nudges, so meal logging always shows a real health/satiety
/// score even without an OpenRouter key. The real OpenRouter service is used
/// automatically instead whenever a key is configured.
struct MockMealNutritionAIService: MealNutritionAIService {
    let providerName = "Mock (offline)"

    func analyze(_ input: MealNutritionAnalysisInput) async throws -> MealNutritionEstimate {
        // Simulate a short analysis delay so the UI flow matches the real provider.
        try await Task.sleep(for: .seconds(0.4))
        return Self.score(input)
    }

    private static let liquidKeywords = ["smoothie", "juice", "shake", "soda", "cola", "milkshake"]
    private static let ultraProcessedKeywords = [
        "instant noodle", "instant ramen", "chips", "candy", "fries", "nugget",
        "soda", "cola", "fried", "frozen dinner", "processed", "hot dog"
    ]

    static func score(_ input: MealNutritionAnalysisInput) -> MealNutritionEstimate {
        let calories = max(input.calories, 1)
        let proteinPer100 = input.protein / calories * 100
        let fiberPer100 = input.fiber / calories * 100
        let sodiumPer100 = input.sodium / calories * 100
        let carbsPer100 = input.carbs / calories * 100

        let text = (input.itemNames.joined(separator: " ") + " " + input.notes).lowercased()
        let isLiquid = liquidKeywords.contains { text.contains($0) }
        let isUltraProcessed = ultraProcessedKeywords.contains { text.contains($0) }

        var health = 55.0
        health += min(20, proteinPer100 * 2.5)
        health += min(15, fiberPer100 * 6)
        health -= min(25, max(0, (sodiumPer100 - 120) / 8))
        if isUltraProcessed { health -= 15 }
        if proteinPer100 < 2 && fiberPer100 < 1 && carbsPer100 > 15 { health -= 10 }
        health = min(100, max(5, health))

        var satiety = 45.0
        satiety += min(30, proteinPer100 * 4)
        satiety += min(20, fiberPer100 * 8)
        if isLiquid { satiety -= 25 }
        if proteinPer100 < 2 && fiberPer100 < 1 { satiety -= 10 }
        satiety = min(100, max(5, satiety))

        var facts: [String] = []
        if proteinPer100 >= 6 { facts.append("High in protein") } else if proteinPer100 < 2 { facts.append("Low in protein") }
        if fiberPer100 >= 2 { facts.append("Good fiber source") } else if fiberPer100 < 0.5 { facts.append("Low fiber") }
        if sodiumPer100 >= 150 { facts.append("Likely high in sodium") }
        if isLiquid { facts.append("Mostly liquid calories") }
        if carbsPer100 >= 15 && proteinPer100 < 3 { facts.append("Mostly fast-digesting carbs") }
        if facts.isEmpty { facts.append("Fairly balanced macros for the calories") }

        var concerns: [String] = []
        if sodiumPer100 >= 150 { concerns.append("Sodium runs high for the calories") }
        if proteinPer100 < 2 { concerns.append("Low protein won't help fullness much") }
        if fiberPer100 < 0.5 && calories > 150 { concerns.append("Low fiber for the calorie load") }
        if isUltraProcessed { concerns.append("Looks ultra-processed") }
        if concerns.isEmpty { concerns.append("No major concerns for a normal balanced diet.") }

        let summary = "[Mock estimate] \(input.mealType.label): \(Int(health.rounded()))/100 health, \(Int(satiety.rounded()))/100 satiety."

        return MealNutritionEstimate(
            healthScore: health.rounded(),
            satietyScore: satiety.rounded(),
            facts: Array(facts.prefix(4)),
            concerns: Array(concerns.prefix(3)),
            summary: summary
        )
    }
}
