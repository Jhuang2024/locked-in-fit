import Foundation

/// Strict JSON contract returned by the AI (or mock) workout-calorie analyzer.
struct WorkoutEstimate: Codable {
    var estimatedCalories: Double
    var calorieLow: Double
    var calorieHigh: Double
    var intensity: String
    var confidence: Double
    var notes: String
}
