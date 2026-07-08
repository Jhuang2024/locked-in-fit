import Foundation

/// Context passed alongside the free-text description to improve the estimate.
struct ExerciseAnalysisContext {
    var units: UnitSystem

    init(units: UnitSystem = .metric) {
        self.units = units
    }
}

/// Strict JSON contract returned by the AI (or mock) exercise-description analyzer.
struct ExerciseEstimate: Codable {
    var name: String
    var movementPattern: String
    var equipment: String
    var muscleGroups: [String]
    var sets: Int
    var reps: Int
    var weightKg: Double
    var confidence: Double
    var notes: String
}

/// Modular exercise-description analysis provider. Swap implementations via
/// AIServiceFactory. Turns a natural-language description ("incline dumbbell
/// press, 3 sets, 10 reps, 45 lb each hand") into a structured entry, so a
/// custom exercise never needs a predefined library entry to exist first.
protocol ExerciseAIService {
    var providerName: String { get }
    func analyzeExercise(description: String, context: ExerciseAnalysisContext) async throws -> ExerciseEstimate
}

/// Deterministic local parser (the same one that used to run inline in the
/// Add Exercise search field), serving as the no-key fallback for the
/// Describe Exercise screen. This is NOT a mock: it parses the real
/// description with the real exercise library and labels its output
/// honestly, so it survives the removal of the fabricating mocks.
struct OfflineExerciseParserService: ExerciseAIService {
    let providerName = "Offline parser"

    func analyzeExercise(description: String, context: ExerciseAnalysisContext) async throws -> ExerciseEstimate {
        try await Task.sleep(for: .seconds(0.6))
        guard let draft = ExerciseDescriptionParser.parse(description, units: context.units) else {
            throw FoodAIError.parsing("Couldn't understand that description. Include a name, sets, reps, and weight.")
        }
        return ExerciseEstimate(
            name: draft.name,
            movementPattern: draft.movementPattern.rawValue,
            equipment: draft.equipment.rawValue,
            muscleGroups: draft.muscleGroups.map(\.rawValue),
            sets: draft.setCount,
            reps: draft.reps,
            weightKg: draft.weightKg,
            confidence: draft.matchedLibrary ? 0.9 : 0.55,
            notes: draft.matchedLibrary ? "Matched to the exercise library." : "Parsed offline (no AI key configured)."
        )
    }
}

extension AIServiceFactory {
    /// Exercise-description analyzer: OpenRouter when a key exists,
    /// otherwise the honest local parser (real parsing, not fabrication).
    static func makeExerciseAnalyzer(settings: UserSettings?) -> ExerciseAIService {
        guard KeychainService.openRouterAPIKey != nil else {
            return OfflineExerciseParserService()
        }
        return OpenRouterExerciseAIService(modelName: modelName(settings: settings))
    }
}
