import Foundation
import UIKit

/// Real appearance analysis via OpenRouter, following the meal/health-scan
/// service pattern. Demands strict JSON, tolerates fences, and is explicitly
/// forbidden from judging attractiveness or inferring protected traits.
struct OpenRouterAppearanceAIService: AppearanceAIService {
    let providerName = "OpenRouter"
    let modelName: String

    private static let sharedRules = """
    You are a supportive, practical appearance-optimization assistant inside a private fitness app. \
    You help the user compare their own photos against their own history — nothing else. \
    Hard rules: never rate attractiveness or human value; never infer or mention race, ethnicity, \
    age, gender identity, or sexuality; never use protected traits in any way; never shame; never \
    recommend crash dieting, dehydration, steroids, disordered eating, or unsafe body-fat targets. \
    Focus on controllables: photo quality/consistency, grooming, skin care basics, posture, sleep, \
    training, and nutrition consistency. \
    Return strict JSON only — no markdown, no code fences, no commentary. \
    scoreAdjustment is a small nudge from -10 to 10 applied to a locally computed score (0 if unsure). \
    confidence is 0-1. observations are 1-4 short neutral strings about lighting/framing/changes vs context. \
    suggestions is an array of 0-4 objects, each specific and actionable (no generic filler): \
    {"title":"...","category":"skin|grooming|posture|workout|nutrition|sleep|body|photo_quality",\
    "explanation":"...","expectedImpact":"...","durationType":"short_term|long_term",\
    "destination":"checklist|calendar|workout_schedule|save_only","priority":1} \
    Respond with exactly this JSON shape: \
    {"scoreAdjustment":0,"confidence":0.75,"observations":["Lighting is uneven"],\
    "suggestions":[{"title":"Use the same lighting tomorrow","category":"photo_quality",\
    "explanation":"Today's lighting reduces comparison confidence.","expectedImpact":"Cleaner score trend.",\
    "durationType":"short_term","destination":"checklist","priority":2}]}
    """

    func analyzeFace(image: UIImage, context: String) async throws -> AppearanceAIResult {
        try await analyze(images: [image],
                          userText: "Face check-in photo. Local analysis summary: \(context). Return the strict JSON.")
    }

    func analyzeBody(images: [UIImage], context: String) async throws -> AppearanceAIResult {
        guard !images.isEmpty else {
            return AppearanceAIResult(scoreAdjustment: 0, confidence: 0, observations: [], suggestions: [])
        }
        return try await analyze(images: images,
                                 userText: "Body check-in photos (front/side/back order where present). Local analysis summary: \(context). Return the strict JSON.")
    }

    private func analyze(images: [UIImage], userText: String) async throws -> AppearanceAIResult {
        guard let apiKey = KeychainService.openRouterAPIKey else { throw FoodAIError.noAPIKey }

        var content: [[String: Any]] = [["type": "text", "text": userText]]
        for image in images.prefix(3) {
            guard let jpeg = image.resized(maxDimension: 1024).jpegData(compressionQuality: 0.7) else { continue }
            content.append(["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]])
        }
        guard content.count > 1 else { throw FoodAIError.parsing("Couldn't encode the photo.") }

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": Self.sharedRules],
                ["role": "user", "content": content]
            ],
            "temperature": 0.3,
            "max_tokens": 1200
        ]

        let response = try await OpenRouterClient.send(body: body, apiKey: apiKey)
        return try Self.parseResult(from: response)
    }

    /// Tolerates code fences and stray text around the JSON object.
    static func parseResult(from content: String) throws -> AppearanceAIResult {
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
            return try JSONDecoder().decode(AppearanceAIResult.self, from: data)
        } catch {
            throw FoodAIError.parsing(error.localizedDescription)
        }
    }
}
