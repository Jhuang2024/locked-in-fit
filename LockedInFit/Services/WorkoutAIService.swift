import Foundation

/// Builds the text description fed to the calorie estimator from what was
/// actually logged (exercises, sets, reps, weight, duration, RPE) instead of
/// a user-typed free-text box, so calories burned are always calculated from
/// the real workout data.
enum WorkoutSummaryBuilder {
    static func describe(_ workout: Workout) -> String {
        var parts = ["\(workout.type.label) workout"]
        if workout.duration > 0 { parts.append("lasting \(Int(workout.duration)) minutes") }
        if workout.perceivedDifficulty > 0 { parts.append("perceived difficulty \(workout.perceivedDifficulty)/10") }
        var text = parts.joined(separator: ", ") + "."

        let exerciseLines = workout.exerciseList.compactMap { exercise -> String? in
            let sets = exercise.setList
            guard !sets.isEmpty else { return exercise.name }
            if exercise.movementPattern == .conditioning || sets.contains(where: { $0.duration > 0 }) {
                let totalSeconds = sets.reduce(0) { $0 + $1.duration }
                return totalSeconds > 0 ? "\(exercise.name) for \(Int(totalSeconds))s" : exercise.name
            }
            let avgReps = sets.reduce(0) { $0 + $1.reps } / max(1, sets.count)
            let maxWeight = sets.map(\.weight).max() ?? 0
            return maxWeight > 0
                ? "\(exercise.name) \(sets.count)x\(avgReps) at \(Int(maxWeight)) kg"
                : "\(exercise.name) \(sets.count)x\(avgReps)"
        }
        if !exerciseLines.isEmpty {
            text += " Exercises: " + exerciseLines.joined(separator: "; ") + "."
        }
        return text
    }
}

/// Context passed alongside the text description to improve the estimate.
struct WorkoutAnalysisContext {
    var workoutType: WorkoutType
    var durationMinutes: Double

    init(workoutType: WorkoutType = .custom, durationMinutes: Double = 0) {
        self.workoutType = workoutType
        self.durationMinutes = durationMinutes
    }
}

/// Modular workout-calorie analysis provider. Swap implementations via AIServiceFactory.
protocol WorkoutAIService {
    var providerName: String { get }
    func analyzeWorkout(description: String, context: WorkoutAnalysisContext) async throws -> WorkoutEstimate
    func testConnection() async throws -> String
}

/// Offline mock so the flow works without a key or network. Scales a rough
/// per-minute rate by a few intensity keywords found in the description.
struct MockWorkoutAIService: WorkoutAIService {
    let providerName = "Mock (offline)"

    private static let highIntensityWords = ["sprint", "hiit", "intervals", "circuit", "heavy", "max", "burpee"]
    private static let lowIntensityWords = ["walk", "stretch", "mobility", "easy", "recovery", "light"]

    func analyzeWorkout(description: String, context: WorkoutAnalysisContext) async throws -> WorkoutEstimate {
        try await Task.sleep(for: .seconds(0.8))
        let lower = description.lowercased()
        var kcalPerMinute = 6.0
        var intensity = "moderate"
        if Self.highIntensityWords.contains(where: { lower.contains($0) }) {
            kcalPerMinute = 10
            intensity = "high"
        } else if Self.lowIntensityWords.contains(where: { lower.contains($0) }) {
            kcalPerMinute = 3
            intensity = "low"
        }
        let minutes = context.durationMinutes > 0 ? context.durationMinutes : 40
        let scale = Double.random(in: 0.9...1.1)
        let calories = (minutes * kcalPerMinute * scale).rounded()
        return WorkoutEstimate(
            estimatedCalories: calories,
            calorieLow: (calories * 0.8).rounded(),
            calorieHigh: (calories * 1.2).rounded(),
            intensity: intensity,
            confidence: 0.5,
            notes: "[Mock estimate] Based on \(Int(minutes)) min at \(intensity) intensity."
        )
    }

    func testConnection() async throws -> String {
        "Mock mode is always available. No network needed."
    }
}

extension AIServiceFactory {
    /// Picks the workout-calorie analyzer. Same mode/key/model source as meal analysis.
    static func makeWorkout(settings: UserSettings?) -> WorkoutAIService {
        let mode = AIMode(rawValue: settings?.aiModeRaw ?? "mock") ?? .mock
        switch mode {
        case .mock:
            return MockWorkoutAIService()
        case .openRouter:
            guard KeychainService.openRouterAPIKey != nil else {
                return MockWorkoutAIService() // no valid key → automatic mock fallback
            }
            let model = settings?.aiModelName.trimmingCharacters(in: .whitespaces) ?? ""
            return OpenRouterWorkoutAIService(modelName: model.isEmpty ? "openai/gpt-4o-mini" : model)
        }
    }
}
