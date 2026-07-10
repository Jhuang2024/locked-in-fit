import Foundation

/// Real workout-calorie analysis via BazaarLink's chat completions API.
/// Sends a plain-text description of the workout, demands strict JSON back,
/// parses into WorkoutEstimate.
struct BazaarLinkWorkoutAIService: WorkoutAIService {
    let providerName = "BazaarLink"
    let modelName: String

    private static let systemPromptText = """
    You are estimating calories burned from a plain-text description of an exercise session for a \
    private fitness tracker. Return strict JSON only; no markdown, no code fences, no commentary. \
    Use the stated workout type and duration as priors, but let the description (exercises, sets/reps, \
    pace, perceived effort) drive the estimate. Estimate conservatively and honestly, and include an \
    uncertainty range rather than pretending precision. \
    Respond with exactly this JSON shape: \
    {"estimatedCalories":320,"calorieLow":260,"calorieHigh":400,"intensity":"moderate",\
    "confidence":0.55,"notes":"Estimate assumes steady effort with standard rest between sets."} \
    intensity must be one of low/moderate/high. All calorie numbers are plain kcal numbers. confidence is 0-1.
    """

    func analyzeWorkout(description: String, context: WorkoutAnalysisContext) async throws -> WorkoutEstimate {
        guard let apiKey = KeychainService.bazaarLinkAPIKey else { throw FoodAIError.noAPIKey }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FoodAIError.parsing("Description is empty.") }

        var userText = "Workout type: \(context.workoutType.label)."
        if context.durationMinutes > 0 {
            userText += " Logged duration: \(Int(context.durationMinutes)) minutes."
        }
        userText += " Description: \(trimmed) Return the strict JSON estimate."

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": Self.systemPromptText],
                ["role": "user", "content": userText]
            ],
            "temperature": 0.2,
            "max_tokens": 800
        ]

        let content = try await BazaarLinkClient.send(body: body, apiKey: apiKey)
        return try Self.parseEstimate(from: content)
    }

    func testConnection() async throws -> String {
        guard let apiKey = KeychainService.bazaarLinkAPIKey else { throw FoodAIError.noAPIKey }
        let body: [String: Any] = [
            "model": modelName,
            "messages": [["role": "user", "content": "Reply with the single word: ok"]],
            "max_tokens": 10
        ]
        let content = try await BazaarLinkClient.send(body: body, apiKey: apiKey)
        return "Connected. \(modelName) replied: \(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
    }

    /// Tolerates code fences and stray text around the JSON object.
    static func parseEstimate(from content: String) throws -> WorkoutEstimate {
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
            return try JSONDecoder().decode(WorkoutEstimate.self, from: data)
        } catch {
            throw FoodAIError.parsing(error.localizedDescription)
        }
    }
}
