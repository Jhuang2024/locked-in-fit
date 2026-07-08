import Foundation
import SwiftData

/// Kicks off health/satiety scoring for a meal right after it's logged,
/// without making the save wait on the network. Call `analyzeInBackground`
/// immediately after `context.insert(meal)` from any entry point (manual,
/// preset, description estimate, or photo estimate): food logging never
/// blocks on this, and a failure just leaves the meal in a "failed" state
/// with a plain-language fallback instead of losing the logged food.
enum MealNutritionAnalysisRunner {
    static func analyzeInBackground(meal: MealLog, settings: UserSettings?, context: ModelContext) {
        Task {
            await analyze(meal: meal, settings: settings, context: context)
        }
    }

    @MainActor
    static func analyze(meal: MealLog, settings: UserSettings?, context: ModelContext) async {
        meal.analysisState = .analyzing
        let service = AIServiceFactory.makeMealNutritionAnalysis(settings: settings)
        let input = MealNutritionAnalysisInput(meal: meal)
        do {
            let estimate = try await service.analyze(input)
            estimate.apply(to: meal)
        } catch {
            meal.analysisState = .failed
            meal.analysisSummary = "AI meal analysis unavailable."
            meal.facts = []
            meal.concerns = []
        }
        try? context.save()
    }
}
