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

/// Offline mock so the flow works without a key or network: reuses the same
/// deterministic local parser that used to run inline in the Add Exercise
/// search field, now serving as the offline fallback for the dedicated
/// Describe Exercise screen.
struct MockExerciseAIService: ExerciseAIService {
    let providerName = "Mock (offline)"

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
    /// Picks the exercise-description analyzer. Same mode/key/model source as meal and workout analysis.
    static func makeExerciseAnalyzer(settings: UserSettings?) -> ExerciseAIService {
        let mode = AIMode(rawValue: settings?.aiModeRaw ?? "mock") ?? .mock
        switch mode {
        case .mock:
            return MockExerciseAIService()
        case .openRouter:
            guard KeychainService.openRouterAPIKey != nil else {
                return MockExerciseAIService() // no valid key → automatic mock fallback
            }
            let model = settings?.aiModelName.trimmingCharacters(in: .whitespaces) ?? ""
            return OpenRouterExerciseAIService(modelName: model.isEmpty ? "openai/gpt-4o-mini" : model)
        }
    }
}
