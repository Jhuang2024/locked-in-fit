import Foundation

/// Real exercise-description analysis via OpenRouter's chat completions API.
/// Sends the plain-text description, demands strict JSON back (name, movement
/// pattern, equipment, muscle groups, sets, reps, weight in kg), and parses
/// into ExerciseEstimate.
struct OpenRouterExerciseAIService: ExerciseAIService {
    let providerName = "OpenRouter"
    let modelName: String

    private static let systemPromptText = """
    You are extracting a structured exercise entry from a free-text description for a private fitness \
    tracker. Return strict JSON only; no markdown, no code fences, no commentary. \
    Infer the exercise name, movement pattern, equipment, and worked muscle groups, plus how many sets, \
    reps, and the weight in kilograms. Convert pounds to kilograms. If the weight is described per hand \
    or per side, report that per-hand/per-side kilogram value, not a doubled total. If no weight is \
    stated, use 0. If sets or reps are not stated, use sensible defaults (3 sets, 8 reps). \
    movementPattern must be exactly one of: squat, hinge, horizontal_push, vertical_push, horizontal_pull, \
    vertical_pull, core, conditioning. \
    equipment must be exactly one of: barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, cardio_machine. \
    muscleGroups is an array using only: chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, \
    calves, core, full_body, cardio. \
    Respond with exactly this JSON shape: \
    {"name":"Incline Dumbbell Press","movementPattern":"horizontal_push","equipment":"dumbbell",\
    "muscleGroups":["chest","shoulders"],"sets":3,"reps":10,"weightKg":20.4,"confidence":0.8,\
    "notes":"Assumed moderate rest between sets."} \
    confidence is 0-1.
    """

    func analyzeExercise(description: String, context: ExerciseAnalysisContext) async throws -> ExerciseEstimate {
        guard let apiKey = KeychainService.openRouterAPIKey else { throw FoodAIError.noAPIKey }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FoodAIError.parsing("Description is empty.") }

        let unitHint = context.units == .imperial ? "If no unit is stated, assume pounds." : "If no unit is stated, assume kilograms."
        let userText = "Description: \(trimmed). \(unitHint) Return the strict JSON result."

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": Self.systemPromptText],
                ["role": "user", "content": userText]
            ],
            "temperature": 0.2,
            "max_tokens": 500
        ]

        let content = try await OpenRouterClient.send(body: body, apiKey: apiKey)
        return try Self.parseEstimate(from: content)
    }

    /// Tolerates code fences and stray text around the JSON object.
    static func parseEstimate(from content: String) throws -> ExerciseEstimate {
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
            return try JSONDecoder().decode(ExerciseEstimate.self, from: data)
        } catch {
            throw FoodAIError.parsing(error.localizedDescription)
        }
    }
}
