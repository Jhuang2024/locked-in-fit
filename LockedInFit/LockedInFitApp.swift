import SwiftUI
import SwiftData

@main
struct LockedInFitApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for:
                MealLog.self, FoodItem.self, FoodPreset.self,
                BodyWeightEntry.self, BodyFatEntry.self, MeasurementEntry.self,
                ProgressPhoto.self, StepEntry.self, ActiveEnergyEntry.self, Goal.self,
                Workout.self, Exercise.self, WorkoutSet.self,
                StrengthScore.self, UserSettings.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        SeedDataService.seedIfNeeded(context: container.mainContext)
        SeedDataService.clearEmptyWorkoutsIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }
            NavigationStack { DailyLogView() }
                .tabItem { Label("Log", systemImage: "fork.knife") }
            NavigationStack { WorkoutDashboardView() }
                .tabItem { Label("Train", systemImage: "dumbbell") }
            NavigationStack { TrendsHomeView() }
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// Trends hub: weekly, weight, goal, body data.
struct TrendsHomeView: View {
    var body: some View {
        List {
            Section("Progress") {
                NavigationLink(destination: GoalDashboardView()) {
                    Label("Goal Dashboard", systemImage: "target")
                }
                NavigationLink(destination: WeightTrendsView()) {
                    Label("Weight Trends", systemImage: "scalemass")
                }
                NavigationLink(destination: WeeklyTrendsView()) {
                    Label("Weekly Trends", systemImage: "calendar")
                }
            }
            Section("Body") {
                NavigationLink(destination: MeasurementsView()) {
                    Label("Measurements", systemImage: "ruler")
                }
                NavigationLink(destination: ProgressPhotosView()) {
                    Label("Progress Photos", systemImage: "photo.on.rectangle")
                }
            }
            Section("Strength") {
                NavigationLink(destination: StrengthScoresView()) {
                    Label("Strength Scores", systemImage: "trophy")
                }
            }
        }
        .navigationTitle("Trends")
    }
}
