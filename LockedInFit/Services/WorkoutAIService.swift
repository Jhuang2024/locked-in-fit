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

extension AIServiceFactory {
    /// Workout-calorie analyzer. No mock: with no key the call throws and
    /// the caller falls back to the local
    /// ActivityAdjustmentCalculator.estimatedWorkoutCalories heuristic,
    /// which is honest local math rather than fabricated AI output.
    static func makeWorkout(settings: UserSettings?) -> WorkoutAIService {
        OpenRouterWorkoutAIService(modelName: modelName(settings: settings))
    }
}
