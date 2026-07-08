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
                WorkoutSchedule.self, WorkoutScheduleSession.self, CalendarConnectionState.self,
                SleepLog.self, NapLog.self)
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
    private enum Tab: Hashable { case today, log, train, looks, trends }

    @State private var selection: Tab = .today
    // Each tab owns its own navigation stack so tabs never share nested state.
    @State private var todayPath = NavigationPath()
    @State private var logPath = NavigationPath()
    @State private var trainPath = NavigationPath()
    @State private var looksPath = NavigationPath()
    @State private var trendsPath = NavigationPath()

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
        }
    }
}

/// Trends hub: weekly, weight, goal, body data. The "This Week" summary is
/// where nutrition, training, appearance, and suggestions converge into one
/// view: trends isn't just weight charts, it's the whole system's readout.
struct TrendsHomeView: View {
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }, sort: \Workout.date, order: .reverse)
    private var completedWorkouts: [Workout]
    @Query(sort: \AppearanceCheckIn.date, order: .reverse) private var appearanceCheckIns: [AppearanceCheckIn]
    @Query private var suggestions: [AppearanceSuggestion]

    private var goal: Goal? { activeGoals.first }
    /// Both "this week" figures below share this exact window (start of the
    /// current calendar week through today) so they describe the same period.
    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? Date().daysAgo(7)
    }
    private var daysElapsedThisWeek: Int {
        max(1, (Calendar.current.dateComponents([.day], from: weekStart, to: Date()).day ?? 0) + 1)
    }
    private var workoutsThisWeek: Int {
        completedWorkouts.filter { $0.date >= weekStart }.count
    }
    /// Days so far this calendar week with a protein target hit, out of days with any meal logged.
    private var proteinHitDaysThisWeek: Int {
        guard let target = goal?.proteinTarget, target > 0 else { return 0 }
        let calendar = Calendar.current
        var count = 0
        var day = weekStart
        while day <= Date() {
            let dayMeals = meals.filter { calendar.isDate($0.date, inSameDayAs: day) }
            if !dayMeals.isEmpty, dayMeals.reduce(0, { $0 + $1.protein }) >= target {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }
    private var faceStreak: Int { AppearanceScoringService.faceStreak(history: appearanceCheckIns) }
    private var pendingSuggestionCount: Int { suggestions.filter { $0.status == .pending }.count }

    var body: some View {
        List {
            Section("This Week") {
                summaryRow("Workouts", "\(workoutsThisWeek)", systemImage: "dumbbell")
                summaryRow("Protein target hit", "\(proteinHitDaysThisWeek)/\(daysElapsedThisWeek) days", systemImage: "fish")
                summaryRow("Face check-in streak", faceStreak > 0 ? "\(faceStreak)d" : "N/A", systemImage: "face.smiling")
                if pendingSuggestionCount > 0 {
                    NavigationLink(destination: AppearanceSuggestionReviewView()) {
                        summaryRow("Pending suggestions", "\(pendingSuggestionCount)", systemImage: "lightbulb")
                    }
                }
            }
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
            Section("Sleep") {
                NavigationLink(destination: SleepTrendsView()) {
                    Label("Sleep Trends", systemImage: "bed.double.fill")
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

    private func summaryRow(_ label: String, _ value: String, systemImage: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
