import Foundation
import SwiftData

/// Recomputes the same numbers DashboardView shows and pushes them to the
/// widget's shared storage. Lets HealthKit-driven syncs keep the widget fresh
/// even when the dashboard tab isn't the one on screen.
enum WidgetSnapshotService {
    @MainActor
    static func refresh(context: ModelContext) {
        let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
        let goal = (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.active })))?.first
        let meals = (try? context.fetch(FetchDescriptor<MealLog>())) ?? []
        let weights = (try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? []
        let steps = (try? context.fetch(FetchDescriptor<StepEntry>())) ?? []
        let activeEnergy = (try? context.fetch(FetchDescriptor<ActiveEnergyEntry>())) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.completed && !$0.isTemplate }))) ?? []

        let viewModel = DashboardViewModel(
            settings: settings,
            goal: goal,
            meals: meals,
            weights: weights,
            steps: steps,
            activeEnergy: activeEnergy,
            workouts: workouts
        )

        WidgetSharedData.save(WidgetSnapshot(
            score: viewModel.lockedInScore,
            caloriesRemaining: Int(viewModel.calories.remaining),
            calorieTarget: Int(viewModel.calories.adjustedTarget),
            steps: viewModel.stepsToday,
            stepTarget: viewModel.stepTarget,
            updatedAt: .now
        ))
    }
}
