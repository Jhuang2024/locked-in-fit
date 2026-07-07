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
                StrengthScore.self, UserSettings.self, HealthScan.self,
                AppearanceCheckIn.self, AppearanceSuggestion.self, DailyChecklistItem.self,
                WorkoutSchedule.self, WorkoutScheduleSession.self, CalendarConnectionState.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        SeedDataService.seedIfNeeded(context: container.mainContext)
        SeedDataService.clearEmptyWorkoutsIfNeeded(context: container.mainContext)
        HealthKitManager.shared.configureAutoSync(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}

struct RootTabView: View {
    private enum Tab: Hashable { case today, log, train, looks, trends, settings }

    @State private var selection: Tab = .today
    // Each tab owns its own navigation stack so tabs never share nested state.
    @State private var todayPath = NavigationPath()
    @State private var logPath = NavigationPath()
    @State private var trainPath = NavigationPath()
    @State private var looksPath = NavigationPath()
    @State private var trendsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    /// Tapping any bottom tab (whether re-tapping the current one or switching
    /// to another) resets that tab to its root screen.
    private var selectionBinding: Binding<Tab> {
        Binding(
            get: { selection },
            set: { newValue in
                resetPath(for: newValue)
                selection = newValue
            })
    }

    private func resetPath(for tab: Tab) {
        switch tab {
        case .today: todayPath = NavigationPath()
        case .log: logPath = NavigationPath()
        case .train: trainPath = NavigationPath()
        case .looks: looksPath = NavigationPath()
        case .trends: trendsPath = NavigationPath()
        case .settings: settingsPath = NavigationPath()
        }
    }

    var body: some View {
        TabView(selection: selectionBinding) {
            NavigationStack(path: $todayPath) { DashboardView() }
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }
                .tag(Tab.today)
            NavigationStack(path: $logPath) { DailyLogView() }
                .tabItem { Label("Log", systemImage: "fork.knife") }
                .tag(Tab.log)
            NavigationStack(path: $trainPath) { WorkoutDashboardView() }
                .tabItem { Label("Train", systemImage: "dumbbell") }
                .tag(Tab.train)
            NavigationStack(path: $looksPath) { LooksDashboardView() }
                .tabItem { Label("Looks", systemImage: "sparkles") }
                .tag(Tab.looks)
            NavigationStack(path: $trendsPath) { TrendsHomeView() }
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(Tab.trends)
            NavigationStack(path: $settingsPath) { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
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
                NavigationLink(destination: CalorieTrendsView()) {
                    Label("Calorie Trends", systemImage: "calendar")
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
            Section("Appearance") {
                NavigationLink(destination: AppearanceTrendsView()) {
                    Label("Appearance Trends", systemImage: "sparkles")
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
