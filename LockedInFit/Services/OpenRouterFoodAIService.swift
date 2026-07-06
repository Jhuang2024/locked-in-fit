import Foundation
import UIKit

/// Real meal analysis via OpenRouter's chat completions API.
/// Sends the photo + context, demands strict JSON back, parses into MealEstimate.
struct OpenRouterFoodAIService: FoodAIService {
    let providerName = "OpenRouter"
    let modelName: String

    private static let systemPrompt = """
    You are estimating calories and macros from a food image for a private nutrition tracker. \
    Return strict JSON only — no markdown, no code fences, no commentary. \
    Estimate conservatively and honestly. Account for hidden cooking oil, especially in \
    home-cooked or restaurant foods (stir-fried vegetables like eggplant absorb large amounts of oil; \
    noodles and sauced rice dishes carry sauce oil; steamed and boiled dishes carry little). \
    Include uncertainty ranges. Do not pretend precision. \
    Respond with exactly this JSON shape: \
    {"mealType":"lunch","estimatedCalories":620,"calorieLow":520,"calorieHigh":820,"protein":38,\
    "carbs":54,"fat":24,"fiber":8,"sodium":900,"confidence":0.68,"hiddenOilLow":80,"hiddenOilHigh":260,\
    "notes":"Estimate includes likely stir-fry oil.","foodItems":[{"name":"stir-fried eggplant",\
    "grams":180,"calories":260,"protein":4,"carbs":22,"fat":18,"fiber":6,"sodium":480,\
    "cookingMethod":"stir-fried","confidence":0.65}]} \
    mealType must be one of breakfast/lunch/dinner/snack. cookingMethod should be one of \
    steamed/boiled/soup/grilled/baked/raw/stir-fried/deep-fried/braised/restaurant_high_oil/unknown. \
    All numbers are plain numbers (kcal, grams, mg for sodium). confidence is 0-1.
    """

    func analyzeMeal(image: UIImage, context: MealAnalysisContext) async throws -> MealEstimate {
        guard let apiKey = KeychainService.openRouterAPIKey else { throw FoodAIError.noAPIKey }
        guard let jpeg = image.resized(maxDimension: 1024).jpegData(compressionQuality: 0.7) else {
            throw FoodAIError.parsing("Couldn't encode the photo.")
        }

        var userText = "Meal type: \(context.mealType.rawValue)."
        if context.isLikelyHomeCooked {
            userText += " This is likely home-cooked or restaurant food — reason explicitly about hidden oil."
        }
        if !context.userDescription.isEmpty {
            userText += " User description: \(context.userDescription)"
        }
        userText += " Analyze the attached photo and return the strict JSON estimate."

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": userText],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]]
                ]]
            ],
            "temperature": 0.2,
            "max_tokens": 1500
        ]

        let content = try await OpenRouterClient.send(body: body, apiKey: apiKey)
        return try Self.parseEstimate(from: content)
    }

    private static let systemPromptText = """
    You are estimating calories and macros from a plain-text description of a meal for a private \
    nutrition tracker. Return strict JSON only — no markdown, no code fences, no commentary. \
    Infer typical portion sizes when the description doesn't state them. Estimate conservatively and \
    honestly. Account for hidden cooking oil, especially in home-cooked or restaurant foods (stir-fried \
    vegetables like eggplant absorb large amounts of oil; noodles and sauced rice dishes carry sauce oil; \
    steamed and boiled dishes carry little). Include uncertainty ranges. Do not pretend precision. \
    Respond with exactly this JSON shape: \
    {"mealType":"lunch","estimatedCalories":620,"calorieLow":520,"calorieHigh":820,"protein":38,\
    "carbs":54,"fat":24,"fiber":8,"sodium":900,"confidence":0.68,"hiddenOilLow":80,"hiddenOilHigh":260,\
    "notes":"Estimate includes likely stir-fry oil.","foodItems":[{"name":"stir-fried eggplant",\
    "grams":180,"calories":260,"protein":4,"carbs":22,"fat":18,"fiber":6,"sodium":480,\
    "cookingMethod":"stir-fried","confidence":0.65}]} \
    mealType must be one of breakfast/lunch/dinner/snack. cookingMethod should be one of \
    steamed/boiled/soup/grilled/baked/raw/stir-fried/deep-fried/braised/restaurant_high_oil/unknown. \
    All numbers are plain numbers (kcal, grams, mg for sodium). confidence is 0-1.
    """

    func analyzeMeal(description: String, context: MealAnalysisContext) async throws -> MealEstimate {
        guard let apiKey = KeychainService.openRouterAPIKey else { throw FoodAIError.noAPIKey }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FoodAIError.parsing("Description is empty.") }

        var userText = "Meal type: \(context.mealType.rawValue). Description: \(trimmed)"
        if context.isLikelyHomeCooked {
            userText += " This is likely home-cooked or restaurant food — reason explicitly about hidden oil."
        }
        userText += " Return the strict JSON estimate."

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": Self.systemPromptText],
                ["role": "user", "content": userText]
            ],
            "temperature": 0.2,
            "max_tokens": 1200
        ]

        let content = try await OpenRouterClient.send(body: body, apiKey: apiKey)
        return try Self.parseEstimate(from: content)
    }

    func testConnection() async throws -> String {
        guard let apiKey = KeychainService.openRouterAPIKey else { throw FoodAIError.noAPIKey }
        let body: [String: Any] = [
            "model": modelName,
            "messages": [["role": "user", "content": "Reply with the single word: ok"]],
            "max_tokens": 10
        ]
        let content = try await OpenRouterClient.send(body: body, apiKey: apiKey)
        return "Connected. \(modelName) replied: \(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
    }

    /// Tolerates code fences and stray text around the JSON object.
    static func parseEstimate(from content: String) throws -> MealEstimate {
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
            return try JSONDecoder().decode(MealEstimate.self, from: data)
        } catch {
            throw FoodAIError.parsing(error.localizedDescription)
        }
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
