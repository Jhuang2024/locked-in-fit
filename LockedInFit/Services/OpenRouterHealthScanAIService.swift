import Foundation
import UIKit

/// Real product-label analysis via OpenRouter's chat completions API.
/// Sends the photo, demands strict JSON back, parses into HealthScanEstimate.
struct OpenRouterHealthScanAIService: HealthScanAIService {
    let providerName = "OpenRouter"
    let modelName: String

    private static let systemPrompt = """
    You are a food-label and nutrition-facts analyst helping someone evaluate a packaged food or \
    product from a photo of its packaging, ingredients list, and/or nutrition facts panel. This is \
    a lookup, not a meal log — the user is deciding whether to buy or eat this product, not confirming \
    they already ate it. Return strict JSON only — no markdown, no code fences, no commentary. \
    Read the ingredients and nutrition facts if visible. If information isn't visible, use your \
    knowledge of the product/brand if recognizable; otherwise make a conservative estimate and lower \
    confidence. \
    healthScore is 0-100 (100 = healthiest) based on nutrient density, processing level, added sugar, \
    sodium, and any concerning additives. \
    satietyScore is 0-100 (100 = extremely filling for its calorie cost — high protein/fiber/water/volume \
    relative to calories; 0 = calorie-dense with little fullness, like candy or oil). \
    processedLevel must be one of unprocessed/minimally_processed/processed/ultra_processed. \
    concerningIngredients should list specific additives or chemicals worth flagging (e.g. artificial \
    dyes, trans fats/partially hydrogenated oil, high-fructose corn syrup, sodium nitrite, artificial \
    sweeteners, excess sodium) — an empty array if nothing notable. \
    Respond with exactly this JSON shape: \
    {"productName":"Example Granola Bar","servingSize":"1 bar (35g)","healthScore":42,"satietyScore":30,\
    "processedLevel":"ultra_processed","calories":150,"protein":2,"carbs":22,"fat":6,"fiber":1,"sugar":12,\
    "sodium":95,"confidence":0.75,"concerningIngredients":["high-fructose corn syrup","artificial flavor"],\
    "notes":"High in added sugar for a small serving; low protein and fiber won't keep you full."} \
    All numbers are plain numbers (kcal, grams, mg for sodium). confidence is 0-1.
    """

    func analyzeProduct(image: UIImage) async throws -> HealthScanEstimate {
        guard let apiKey = KeychainService.openRouterAPIKey else { throw FoodAIError.noAPIKey }
        guard let jpeg = image.resized(maxDimension: 1024).jpegData(compressionQuality: 0.7) else {
            throw FoodAIError.parsing("Couldn't encode the photo.")
        }

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": "Analyze this product photo (packaging/ingredients/nutrition label) and return the strict JSON estimate."],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]]
                ]]
            ],
            "temperature": 0.2,
            "max_tokens": 1200
        ]

        let content = try await OpenRouterClient.send(body: body, apiKey: apiKey)
        return try Self.parseEstimate(from: content)
    }

    private static let systemPromptText = """
    You are a food-label and nutrition-facts analyst helping someone evaluate a packaged food or \
    product from a plain-text name/description (no photo provided). This is a lookup, not a meal log — \
    the user is deciding whether to buy or eat this product, not confirming they already ate it. \
    Return strict JSON only — no markdown, no code fences, no commentary. \
    Use your knowledge of the named product/brand if recognizable; otherwise make a conservative, honest \
    estimate for a typical product matching the description and lower confidence accordingly. \
    healthScore is 0-100 (100 = healthiest) based on nutrient density, processing level, added sugar, \
    sodium, and any concerning additives. \
    satietyScore is 0-100 (100 = extremely filling for its calorie cost — high protein/fiber/water/volume \
    relative to calories; 0 = calorie-dense with little fullness, like candy or oil). \
    processedLevel must be one of unprocessed/minimally_processed/processed/ultra_processed. \
    concerningIngredients should list specific additives or chemicals worth flagging (e.g. artificial \
    dyes, trans fats/partially hydrogenated oil, high-fructose corn syrup, sodium nitrite, artificial \
    sweeteners, excess sodium) — an empty array if nothing notable. \
    Respond with exactly this JSON shape: \
    {"productName":"Example Granola Bar","servingSize":"1 bar (35g)","healthScore":42,"satietyScore":30,\
    "processedLevel":"ultra_processed","calories":150,"protein":2,"carbs":22,"fat":6,"fiber":1,"sugar":12,\
    "sodium":95,"confidence":0.6,"concerningIngredients":["high-fructose corn syrup","artificial flavor"],\
    "notes":"High in added sugar for a small serving; low protein and fiber won't keep you full."} \
    All numbers are plain numbers (kcal, grams, mg for sodium). confidence is 0-1.
    """

    func analyzeProduct(description: String) async throws -> HealthScanEstimate {
        guard let apiKey = KeychainService.openRouterAPIKey else { throw FoodAIError.noAPIKey }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FoodAIError.parsing("Description is empty.") }

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": Self.systemPromptText],
                ["role": "user", "content": "Product: \(trimmed). Return the strict JSON estimate."]
            ],
            "temperature": 0.2,
            "max_tokens": 1000
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
        return "Connected — \(modelName) replied: \(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
    }

    /// Tolerates code fences and stray text around the JSON object.
    static func parseEstimate(from content: String) throws -> HealthScanEstimate {
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
            return try JSONDecoder().decode(HealthScanEstimate.self, from: data)
        } catch {
            throw FoodAIError.parsing(error.localizedDescription)
        }
    }
}
