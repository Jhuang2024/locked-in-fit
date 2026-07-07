import Foundation

/// Strict JSON contract returned by the AI (or mock) meal health/satiety scorer.
/// Runs after a meal's calories/macros are already known (manual entry, photo
/// estimate, or description estimate) — this only adds the score/facts layer
/// on top, it never re-estimates calories itself.
struct MealNutritionEstimate: Codable {
    var healthScore: Double
    var satietyScore: Double
    var facts: [String]
    var concerns: [String]
    var summary: String

    /// Applies the estimate to an already-saved meal. Called after review, so
    /// scores/facts land alongside the meal the user actually logged.
    func apply(to meal: MealLog) {
        meal.healthScore = min(100, max(0, healthScore))
        meal.satietyScore = min(100, max(0, satietyScore))
        meal.facts = Array(facts.prefix(4))
        meal.concerns = Array(concerns.prefix(3))
        meal.analysisSummary = summary
        meal.analysisState = .completed
    }
}
