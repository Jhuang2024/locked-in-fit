import Foundation
import UIKit

/// Real meal analysis via AIGatewayClient (OpenRouter, falling back to
/// BazaarLink). Sends the photo + context, demands strict JSON back, parses
/// into MealEstimate.
struct BazaarLinkFoodAIService: FoodAIService {
    /// Best-effort label for "who will this try first": read at
    /// construction time, before any network call, so it can't reflect a
    /// fallback that hasn't happened yet. AIGatewayClient itself always
    /// tries OpenRouter before BazaarLink regardless of this label.
    var providerName: String { KeychainService.openRouterAPIKey != nil ? "OpenRouter" : "BazaarLink" }
    /// User's explicit model override from Settings, if any; nil/empty lets
    /// AIGatewayClient pick each provider's own free-routing model.
    let modelOverride: String?

    private static let systemPrompt = """
    You are estimating calories and macros from a food image for a private nutrition tracker. \
    Return strict JSON only; no markdown, no code fences, no commentary. \
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

    func analyzeMeal(images: [UIImage], context: MealAnalysisContext) async throws -> MealEstimate {
        guard !images.isEmpty else { throw FoodAIError.parsing("No photos to analyze.") }
        let jpegs = images.compactMap { $0.resized(maxDimension: 1024).jpegData(compressionQuality: 0.7) }
        guard jpegs.count == images.count else {
            throw FoodAIError.parsing("Couldn't encode one of the photos.")
        }

        var userText = "Meal type: \(context.mealType.rawValue)."
        if images.count > 1 {
            userText += " This ONE meal is shown across \(images.count) photos (multiple dishes, or the same"
            userText += " spread from different angles). Produce a SINGLE combined estimate covering everything"
            userText += " eaten, counting each distinct dish exactly once even if it appears in more than one photo."
        }
        if context.isLikelyHomeCooked {
            userText += " This is likely home-cooked or restaurant food; reason explicitly about hidden oil."
        }
        if !context.userDescription.isEmpty {
            userText += " User description: \(context.userDescription)"
        }
        userText += " Analyze the attached photo\(images.count > 1 ? "s" : "") and return the strict JSON estimate."

        var userContent: [[String: Any]] = [["type": "text", "text": userText]]
        for jpeg in jpegs {
            userContent.append(["type": "image_url",
                                "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]])
        }

        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.2,
            "max_tokens": 1500
        ]

        let result = try await AIGatewayClient.send(body: body, modelOverride: modelOverride)
        return try Self.parseEstimate(from: result.content)
    }

    private static let systemPromptText = """
    You are estimating calories and macros from a plain-text description of a meal for a private \
    nutrition tracker. Return strict JSON only; no markdown, no code fences, no commentary. \
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
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FoodAIError.parsing("Description is empty.") }

        var userText = "Meal type: \(context.mealType.rawValue). Description: \(trimmed)"
        if context.isLikelyHomeCooked {
            userText += " This is likely home-cooked or restaurant food; reason explicitly about hidden oil."
        }
        userText += " Return the strict JSON estimate."

        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": Self.systemPromptText],
                ["role": "user", "content": userText]
            ],
            "temperature": 0.2,
            "max_tokens": 1200
        ]

        let result = try await AIGatewayClient.send(body: body, modelOverride: modelOverride)
        return try Self.parseEstimate(from: result.content)
    }

    func testConnection() async throws -> String {
        let body: [String: Any] = [
            "messages": [["role": "user", "content": "Reply with the single word: ok"]],
            "max_tokens": 10
        ]
        let result = try await AIGatewayClient.send(body: body, modelOverride: modelOverride)
        return "Connected via \(result.provider.displayName) (\(result.model)). Replied: \(result.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
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
