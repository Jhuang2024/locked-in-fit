import Foundation

/// Health/satiety scoring for an already-logged meal via AIGatewayClient
/// (OpenRouter, falling back to BazaarLink). Reuses the same request/parsing
/// plumbing as BazaarLinkFoodAIService and BazaarLinkHealthScanAIService.
/// Only needs the meal's final numbers, not another photo round-trip, so it
/// stays fast and never blocks the food-logging flow.
struct BazaarLinkMealNutritionAIService: MealNutritionAIService {
    var providerName: String { KeychainService.openRouterAPIKey != nil ? "OpenRouter" : "BazaarLink" }
    let modelOverride: String?

    private static let systemPrompt = """
    You are a practical nutrition coach scoring a meal or snack the user already logged in a \
    private nutrition tracker. This is feedback on food they already ate, not a diagnosis. Return \
    strict JSON only; no markdown, no code fences, no commentary. \
    healthScore is 0-100 (100 = healthiest): reward nutrient density, minimally processed \
    ingredients, good protein, fiber, micronutrients, healthy fats, reasonable calories, and \
    balanced macros. Penalize ultra-processed food, excessive added sugar, excessive sodium, trans \
    fats, poor protein/fiber, very low nutritional value, or an obviously unbalanced meal. Do not \
    penalize a meal just for being calorie-dense if it's nutritious. \
    satietyScore is 0-100 (100 = very filling): reward high protein, high fiber, food volume, \
    slow-digesting carbs, and healthy fats. Penalize liquid calories, refined carbs, sugary \
    snacks, low protein, and low fiber. Weigh the portion size given, not just macro ratios. \
    facts is 2-4 short, plain-language facts about the meal, e.g. "High in protein", "Good fiber \
    source", "Mostly fast-digesting carbs", "Likely high in sodium", "Low micronutrient density". \
    concerns is 1-3 short, non-alarmist notes on real issues (e.g. high sodium, low protein, low \
    fiber, added sugar, excessive saturated fat, low calorie density for someone trying to gain \
    weight, very low overall calories). If nothing stands out, return a single entry like "No \
    major concerns for a normal balanced diet." Never use extreme or alarming language (never call \
    a meal "dangerous"); be blunt and useful, not medical. \
    summary is one short, practical sentence capturing the overall take. \
    Respond with exactly this JSON shape: \
    {"healthScore":72,"satietyScore":65,"facts":["Good protein for the calories","Decent fiber \
    from the vegetables","Some sodium from the sauce"],"concerns":["Sodium runs a bit high"],\
    "summary":"Solid, balanced meal with good protein; watch the sodium."} \
    All scores are plain numbers, 0-100.
    """

    private static let strictSystemPrompt = systemPrompt + " IMPORTANT: Your entire response must " +
        "be a single valid JSON object and nothing else - no explanation, no markdown, no text " +
        "outside the JSON object."

    func analyze(_ input: MealNutritionAnalysisInput) async throws -> MealNutritionEstimate {
        do {
            return try await requestAndParse(input: input, strict: false)
        } catch FoodAIError.parsing {
            // Parsing failed once; retry with a stricter prompt before giving up.
            return try await requestAndParse(input: input, strict: true)
        }
    }

    private func requestAndParse(input: MealNutritionAnalysisInput, strict: Bool) async throws -> MealNutritionEstimate {
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": strict ? Self.strictSystemPrompt : Self.systemPrompt],
                ["role": "user", "content": Self.describe(input)]
            ],
            "temperature": strict ? 0.0 : 0.2,
            "max_tokens": 700
        ]
        let result = try await AIGatewayClient.send(body: body, modelOverride: modelOverride)
        return try Self.parseEstimate(from: result.content)
    }

    private static func describe(_ input: MealNutritionAnalysisInput) -> String {
        var text = "Meal type: \(input.mealType.rawValue). "
        if !input.itemNames.isEmpty {
            text += "Foods: \(input.itemNames.joined(separator: ", ")). "
        }
        text += "Calories: \(Int(input.calories)) kcal, protein: \(Int(input.protein))g, " +
                "carbs: \(Int(input.carbs))g, fat: \(Int(input.fat))g, fiber: \(Int(input.fiber))g, " +
                "sodium: \(Int(input.sodium))mg."
        if !input.notes.isEmpty {
            text += " Notes: \(input.notes)"
        }
        text += " Score this meal and return the strict JSON estimate."
        return text
    }

    /// Tolerates code fences and stray text around the JSON object.
    static func parseEstimate(from content: String) throws -> MealNutritionEstimate {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        guard let data = text.data(using: .utf8) else {
            throw FoodAIError.parsing("Empty response.")
        }
        do {
            return try JSONDecoder().decode(MealNutritionEstimate.self, from: data)
        } catch {
            throw FoodAIError.parsing(error.localizedDescription)
        }
    }
}
