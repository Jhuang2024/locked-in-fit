import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \StepEntry.date, order: .reverse) private var steps: [StepEntry]
    @Query(sort: \ActiveEnergyEntry.date, order: .reverse) private var activeEnergy: [ActiveEnergyEntry]
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }, sort: \Workout.date, order: .reverse)
    private var completedWorkouts: [Workout]
    @Query private var strengthScores: [StrengthScore]

    @State private var showAddMeal = false
    @State private var showPhotoAnalysis = false

    private var settings: UserSettings? { settingsList.first }
    private var goal: Goal? { activeGoals.first }
    private var viewModel: DashboardViewModel {
        DashboardViewModel(
            settings: settings,
            goal: goal,
            meals: meals,
            weights: weights,
            steps: steps,
            activeEnergy: activeEnergy,
            workouts: completedWorkouts
        )
    }

    private var todayMeals: [MealLog] { meals.filter { $0.date.isToday } }

    private var maintenance: Double {
        guard let settings else { return 2400 }
        return Analytics.estimateMaintenance(settings: settings, weights: weights, meals: meals, steps: steps)
    }

    private var calorieTarget: Double { goal?.calorieTarget ?? maintenance }
    private var proteinTarget: Double { goal?.proteinTarget ?? 140 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                quickActions
                calorieCard
                macroCard
                activityCard
                trendCard
                if let goal {
                    goalSnippet(goal)
                }
                mealsCard
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showPhotoAnalysis = true } label: { Image(systemName: "camera") }
                Button { showAddMeal = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddMeal) { AddMealView() }
        .sheet(isPresented: $showPhotoAnalysis) { MealPhotoAnalysisView() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AppBrandMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date.now.formatted(date: .complete, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(goal?.phase.label ?? "No active phase")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                Label("\(viewModel.lockedInScore)", systemImage: "lock.fill")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .accessibilityLabel("Locked In Score \(viewModel.lockedInScore)")
            }

            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: Double(viewModel.lockedInScore) / 100)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(viewModel.lockedInScore)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 6) {
                    scoreRow("Calories", done: viewModel.nutrition.calories > 0 && abs(viewModel.nutrition.calories - viewModel.calories.adjustedTarget) / max(viewModel.calories.adjustedTarget, 1) < 0.15)
                    scoreRow("Protein \(Int(viewModel.nutrition.protein))/\(Int(proteinTarget))g", done: viewModel.nutrition.protein >= proteinTarget)
                    scoreRow("Steps \(viewModel.stepsToday)/\(viewModel.stepTarget)", done: viewModel.stepsToday >= viewModel.stepTarget)
                    scoreRow("Workouts today \(viewModel.completedWorkoutsToday)", done: viewModel.completedWorkoutsToday > 0)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button { showAddMeal = true } label: {
                Label("Meal", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button { createBlankWorkout() } label: {
                Label("Workout", systemImage: "dumbbell.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private func scoreRow(_ label: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(done ? .green : .secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(done ? .primary : .secondary)
        }
    }

    private var calorieCard: some View {
        DashboardCard(title: "Calories Remaining", systemImage: "flame") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(viewModel.calories.remaining))")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(viewModel.calories.remaining < 0 ? .red : .primary)
                    Text("kcal left")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                ProgressView(value: min(viewModel.nutrition.calories, viewModel.calories.adjustedTarget), total: max(viewModel.calories.adjustedTarget, 1))
                    .tint(viewModel.nutrition.calories > viewModel.calories.adjustedTarget ? .red : .accentColor)
                HStack {
                    StatChip(label: "Eaten", value: "\(Int(viewModel.nutrition.calories))")
                    StatChip(label: "Base", value: "\(Int(viewModel.calories.baseTarget))")
                    StatChip(label: "Adjustment", value: "+\(Int(viewModel.calories.exerciseAdjustment))")
                    StatChip(label: "Target", value: "\(Int(viewModel.calories.adjustedTarget))")
                }
                Label(adjustmentLabel, systemImage: viewModel.activity.isEstimated ? "waveform.path.ecg" : "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.nutrition.hiddenOilHigh > 0 {
                    Label("Hidden oil could add +\(Int(viewModel.nutrition.hiddenOilLow))-\(Int(viewModel.nutrition.hiddenOilHigh)) kcal today", systemImage: "drop.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Estimated maintenance: \(Int(maintenance)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var adjustmentLabel: String {
        let prefix = settings?.exerciseCalorieAdjustment.label ?? ExerciseCalorieAdjustment.conservative.label
        let base = "\(prefix): \(Int(viewModel.activity.adjustmentCalories)) kcal added from \(viewModel.activity.sourceLabel.lowercased())"
        return viewModel.activity.isEstimated ? base + " (estimate)" : base
    }

    private var macroCard: some View {
        DashboardCard(title: "Macros", systemImage: "chart.pie") {
            HStack {
                MacroRingView(label: "Protein", current: viewModel.nutrition.protein, target: proteinTarget, unit: "g", color: .red)
                Spacer()
                MacroRingView(label: "Carbs", current: viewModel.nutrition.carbs, target: max(1, (calorieTarget * 0.4) / 4), unit: "g", color: .blue)
                Spacer()
                MacroRingView(label: "Fat", current: viewModel.nutrition.fat, target: max(1, (calorieTarget * 0.25) / 9), unit: "g", color: .yellow)
                Spacer()
                MacroRingView(label: "Fiber", current: viewModel.nutrition.fiber, target: 30, unit: "g", color: .green)
            }
        }
    }

    private var activityCard: some View {
        DashboardCard(title: "Activity", systemImage: "figure.walk") {
            HStack {
                StatChip(label: "Steps", value: "\(viewModel.stepsToday)/\(viewModel.stepTarget)")
                StatChip(label: viewModel.activity.isEstimated ? "Est. active" : "Active energy", value: "\(Int(viewModel.activity.baseActiveCalories))")
                StatChip(label: "Workouts", value: "\(viewModel.completedWorkoutsToday)")
            }
        }
    }

    private var trendCard: some View {
        DashboardCard(title: "Trends", systemImage: "chart.line.uptrend.xyaxis") {
            HStack {
                let trend = WeightTrendCalculator.currentTrendKg(entries: weights)
                StatChip(label: "Weight trend", value: trend.map { Formatters.kg($0) } ?? "Log weight")
                StatChip(label: "7-day calories", value: viewModel.weeklyCalorieAverage.map { "\(Int($0))" } ?? "No meals")
                StatChip(label: "Adherence", value: adherenceLabel)
            }
            NavigationLink(destination: WeightTrendsView()) {
                Label("Log weight", systemImage: "scalemass")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 6)
        }
    }

    private var adherenceLabel: String {
        guard viewModel.nutrition.calories > 0 else { return "No logs" }
        let deviation = abs(viewModel.nutrition.calories - viewModel.calories.adjustedTarget) / max(viewModel.calories.adjustedTarget, 1)
        return deviation <= 0.1 ? "On track" : deviation <= 0.2 ? "Close" : "Review"
    }

    private func goalSnippet(_ goal: Goal) -> some View {
        NavigationLink(destination: GoalDashboardView()) {
            DashboardCard(title: "\(goal.phase.label) Progress", systemImage: goal.phase.systemImage) {
                HStack {
                    let trend = WeightTrendCalculator.currentTrendKg(entries: weights)
                    StatChip(label: "Trend weight", value: trend.map { Formatters.kg($0) } ?? "—")
                    StatChip(label: "Target", value: Formatters.kg(goal.targetWeightKg))
                    let rate = WeightTrendCalculator.weeklyRate(entries: weights)
                    StatChip(label: "Per week", value: rate.map { Formatters.kgChange($0) } ?? "—",
                             color: rateColor(rate, goal: goal))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func rateColor(_ rate: Double?, goal: Goal) -> Color {
        guard let rate else { return .primary }
        let target = goal.weeklyWeightChangeTarget
        if abs(target) < 0.05 { return abs(rate) < 0.15 ? .green : .orange }
        return rate / target > 0.5 ? .green : .orange
    }

    private var mealsCard: some View {
        DashboardCard(title: "Today's Meals", systemImage: "fork.knife") {
            if todayMeals.isEmpty {
                EmptyStateView(systemImage: "fork.knife.circle", title: "No meals logged yet", message: "Add your first meal or analyze a photo when you eat.")
            } else {
                VStack(spacing: 10) {
                    ForEach(todayMeals) { meal in
                        NavigationLink(destination: MealDetailView(meal: meal)) {
                            MealRowView(meal: meal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func createBlankWorkout() {
        context.insert(Workout(date: .now, title: "Workout", type: .custom))
    }
}
