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
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }, sort: \Workout.date, order: .reverse)
    private var completedWorkouts: [Workout]
    @Query private var strengthScores: [StrengthScore]

    @State private var showAddMeal = false
    @State private var showPhotoAnalysis = false

    private var settings: UserSettings? { settingsList.first }
    private var goal: Goal? { activeGoals.first }

    private var todayMeals: [MealLog] { meals.filter { $0.date.isToday } }
    private var todayCalories: Double { todayMeals.reduce(0) { $0 + $1.calories } }
    private var todayProtein: Double { todayMeals.reduce(0) { $0 + $1.protein } }
    private var todayCarbs: Double { todayMeals.reduce(0) { $0 + $1.carbs } }
    private var todayFat: Double { todayMeals.reduce(0) { $0 + $1.fat } }
    private var todayOilLow: Double { todayMeals.reduce(0) { $0 + $1.hiddenOilLow } }
    private var todayOilHigh: Double { todayMeals.reduce(0) { $0 + $1.hiddenOilHigh } }
    private var todaySteps: Int { steps.first(where: { $0.date.isToday })?.steps ?? 0 }

    private var workoutsThisWeek: Int {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? Date().daysAgo(7)
        return completedWorkouts.filter { $0.date >= weekStart }.count
    }

    private var maintenance: Double {
        guard let settings else { return 2400 }
        return Analytics.estimateMaintenance(settings: settings, weights: weights, meals: meals, steps: steps)
    }

    private var calorieTarget: Double { goal?.calorieTarget ?? maintenance }
    private var proteinTarget: Double { goal?.proteinTarget ?? 140 }
    private var stepTarget: Int { goal?.stepTarget ?? 8000 }

    private var lockedInScore: Int {
        Analytics.lockedInScore(
            todayCalories: todayCalories, calorieTarget: calorieTarget,
            todayProtein: todayProtein, proteinTarget: proteinTarget,
            todaySteps: todaySteps, stepTarget: stepTarget,
            trainedThisWeek: workoutsThisWeek, weeklyTrainingTarget: 4)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                lockedInCard
                calorieCard
                macroCard
                if let goal {
                    goalSnippet(goal)
                }
                mealsCard
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Locked In Fit")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showPhotoAnalysis = true } label: { Image(systemName: "camera") }
                Button { showAddMeal = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddMeal) { AddMealView() }
        .sheet(isPresented: $showPhotoAnalysis) { MealPhotoAnalysisView() }
    }

    private var lockedInCard: some View {
        DashboardCard(title: "Locked In Score", systemImage: "lock.fill") {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: Double(lockedInScore) / 100)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(lockedInScore)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 6) {
                    scoreRow("Calories", done: todayCalories > 0 && abs(todayCalories - calorieTarget) / max(calorieTarget, 1) < 0.15)
                    scoreRow("Protein \(Int(todayProtein))/\(Int(proteinTarget))g", done: todayProtein >= proteinTarget)
                    scoreRow("Steps \(todaySteps)/\(stepTarget)", done: todaySteps >= stepTarget)
                    scoreRow("Training \(workoutsThisWeek)/4 this week", done: workoutsThisWeek >= 4)
                }
                Spacer()
            }
        }
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
        DashboardCard(title: "Today's Intake", systemImage: "flame") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(todayCalories))")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("/ \(Int(calorieTarget)) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(calorieTarget - todayCalories)) left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(todayCalories > calorieTarget ? .red : .green)
                }
                ProgressView(value: min(todayCalories, calorieTarget), total: max(calorieTarget, 1))
                    .tint(todayCalories > calorieTarget ? .red : .accentColor)
                if todayOilHigh > 0 {
                    Label("Hidden oil could add +\(Int(todayOilLow))–\(Int(todayOilHigh)) kcal today", systemImage: "drop.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Estimated maintenance: \(Int(maintenance)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var macroCard: some View {
        DashboardCard(title: "Macros", systemImage: "chart.pie") {
            HStack {
                MacroRingView(label: "Protein", current: todayProtein, target: proteinTarget, unit: "g", color: .red)
                Spacer()
                MacroRingView(label: "Carbs", current: todayCarbs, target: max(1, (calorieTarget * 0.4) / 4), unit: "g", color: .blue)
                Spacer()
                MacroRingView(label: "Fat", current: todayFat, target: max(1, (calorieTarget * 0.25) / 9), unit: "g", color: .yellow)
                Spacer()
                MacroRingView(label: "Fiber", current: todayMeals.reduce(0) { $0 + $1.fiber }, target: 30, unit: "g", color: .green)
            }
        }
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
                Text("Nothing logged yet. Add a meal or snap a photo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
}
