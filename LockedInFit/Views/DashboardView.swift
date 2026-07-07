import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \BodyFatEntry.date) private var bodyFats: [BodyFatEntry]
    @Query(sort: \StepEntry.date, order: .reverse) private var steps: [StepEntry]
    @Query(sort: \ActiveEnergyEntry.date, order: .reverse) private var activeEnergy: [ActiveEnergyEntry]
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }, sort: \Workout.date, order: .reverse)
    private var completedWorkouts: [Workout]
    @Query(filter: #Predicate<Workout> { !$0.isTemplate }, sort: \Workout.date, order: .reverse)
    private var allWorkouts: [Workout]
    @Query private var strengthScores: [StrengthScore]
    @Query(sort: \AppearanceCheckIn.date, order: .reverse) private var appearanceCheckIns: [AppearanceCheckIn]
    @Query private var appearanceSuggestions: [AppearanceSuggestion]
    @Query private var checklistItems: [DailyChecklistItem]
    @Query private var workoutSchedules: [WorkoutSchedule]

    @State private var showAddMeal = false
    @State private var showPhotoAnalysis = false
    @State private var showLogWeight = false
    @State private var newWeight = ""
    @State private var healthKit = HealthKitManager.shared
    @State private var activeWorkout: Workout?
    @State private var actionTick = 0

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

    private var faceCheckedInToday: Bool {
        appearanceCheckIns.contains { $0.kind == .face && $0.date.isToday }
    }
    private var latestFaceCheckIn: AppearanceCheckIn? { appearanceCheckIns.first { $0.kind == .face } }
    private var latestBodyCheckIn: AppearanceCheckIn? { appearanceCheckIns.first { $0.kind == .body } }
    /// Falls back to a composition-only score (weight/body fat) when the user
    /// hasn't run a body check-in yet, so a body score exists without a photo.
    private var liveBodyScore: AppearanceScoringService.BodyScoreResult? {
        AppearanceScoringService.liveBodyScore(weights: weights, bodyFats: bodyFats, workouts: completedWorkouts, settings: settings, goal: goal)
    }
    private var displayedBodyScore: Double? {
        AppearanceScoringService.effectiveBodyScore(checkIn: latestBodyCheckIn, live: liveBodyScore)
    }
    /// Same formula the Looks page uses for its "Combined" ring, so the two never disagree.
    private var overallLooksScore: Double? {
        AppearanceScoringService.combinedScore(face: latestFaceCheckIn, body: latestBodyCheckIn, liveBody: liveBodyScore)
    }
    private var pendingSuggestionCount: Int {
        appearanceSuggestions.filter { $0.status == .pending }.count
    }
    private var sessionsDueToday: [WorkoutScheduleSession] {
        WorkoutScheduleGeneratorService.sessionsDue(schedules: workoutSchedules)
    }

    private var maintenance: Double {
        guard let settings else { return 2400 }
        return Analytics.estimateMaintenance(settings: settings, weights: weights, meals: meals, steps: steps)
    }

    private var calorieTarget: Double { goal?.calorieTarget ?? maintenance }
    private var proteinTarget: Double { goal?.proteinTarget ?? 140 }
    private var sodiumLimit: Double { max(1, settings?.sodiumLimitMg ?? 2300) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                quickActions
                checklistCard
                calorieCard
                macroCard
                activityCard
                looksCard
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
        .refreshable { await healthKit.sync(context: context) }
        .task { await refreshReminderSchedules() }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showAddMeal) { AddMealView() }
        .sheet(isPresented: $showPhotoAnalysis) { MealPhotoAnalysisView() }
        .sheet(item: $activeWorkout) { workout in
            NavigationStack { WorkoutLogView(workout: workout) }
        }
        .alert("Log Weigh-In", isPresented: $showLogWeight) {
            TextField("Weight (kg)", text: $newWeight)
                .keyboardType(.decimalPad)
            Button("Save") { saveWeight() }
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.selection, trigger: actionTick)
    }

    /// Keep the rolling 14-day local reminder windows topped up. Never prompts
    /// for permission; NotificationService skips scheduling if not authorized.
    private func refreshReminderSchedules() async {
        guard let settings else { return }
        await NotificationService.refreshFaceReminders(
            enabled: settings.faceReminderEnabled,
            hour: settings.faceReminderHour,
            minute: settings.faceReminderMinute,
            faceCheckedInToday: faceCheckedInToday)
        for schedule in workoutSchedules where schedule.isActive {
            await NotificationService.refreshWorkoutReminders(
                schedule: schedule,
                enabled: settings.workoutRemindersEnabled,
                offsetMinutes: settings.defaultWorkoutReminderMinutes)
        }
    }

    private func saveWeight() {
        defer { newWeight = "" }
        guard let kg = Double(newWeight), kg > 20, kg < 300 else { return }
        context.insert(BodyWeightEntry(date: .now, weightKg: kg, source: .manual))
        Task { await HealthKitManager.shared.writeWeight(kg, date: .now) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AppBrandMark(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Date.now.formatted(date: .complete, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(goal?.phase.label ?? "No active phase")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
            }

            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: Double(viewModel.lockedInScore) / 100)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: viewModel.lockedInScore)
                    VStack(spacing: 0) {
                        Text("\(viewModel.lockedInScore)")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("SCORE")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                    }
                }
                .frame(width: 72, height: 72)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Locked In Score \(viewModel.lockedInScore) of 100")

                VStack(alignment: .leading, spacing: 6) {
                    scoreRow("Calories", done: viewModel.nutrition.calories > 0 && abs(viewModel.nutrition.calories - viewModel.calories.adjustedTarget) / max(viewModel.calories.adjustedTarget, 1) < 0.15)
                    scoreRow("Protein \(Int(viewModel.nutrition.protein))/\(Int(proteinTarget))g", done: viewModel.nutrition.protein >= proteinTarget)
                    scoreRow("Sodium \(Int(viewModel.nutrition.sodium))/\(Int(sodiumLimit))mg", done: viewModel.nutrition.sodium <= sodiumLimit)
                    scoreRow("Steps \(viewModel.stepsToday)/\(viewModel.stepTarget)", done: viewModel.stepsToday >= viewModel.stepTarget)
                    scoreRow("Workout today", done: viewModel.completedWorkoutsToday > 0)
                }
                Spacer()
            }
        }
        .padding(16)
        .cardBackground()
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            quickActionButton("Meal", systemImage: "fork.knife", prominent: true) { showAddMeal = true }
            quickActionButton("Photo", systemImage: "camera.fill") { showPhotoAnalysis = true }
            quickActionButton("Workout", systemImage: "dumbbell.fill") { createBlankWorkout() }
            quickActionButton("Weight", systemImage: "scalemass.fill") { showLogWeight = true }
            quickActionButton("Sync", systemImage: "arrow.triangle.2.circlepath", spinning: healthKit.syncing, badge: healthKit.autoSyncEnabled) {
                Task { await healthKit.sync(context: context) }
            }
        }
    }

    private func quickActionButton(_ label: String, systemImage: String, prominent: Bool = false, spinning: Bool = false, badge: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            actionTick += 1
            action()
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolEffect(.pulse, isActive: spinning)
                    if badge {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .offset(x: 7, y: -3)
                    }
                }
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.black : Color.primary)
            .background(
                prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.pressable)
        .disabled(spinning)
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
                MacroRingView(label: "Protein", current: viewModel.nutrition.protein, target: proteinTarget, unit: "g", color: .accentColor)
                Spacer()
                MacroRingView(label: "Carbs", current: viewModel.nutrition.carbs, target: max(1, (calorieTarget * 0.4) / 4), unit: "g", color: .indigo)
                Spacer()
                MacroRingView(label: "Fat", current: viewModel.nutrition.fat, target: max(1, (calorieTarget * 0.25) / 9), unit: "g", color: .orange)
                Spacer()
                MacroRingView(label: "Fiber", current: viewModel.nutrition.fiber, target: 30, unit: "g", color: .teal)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Sodium", systemImage: "drop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.nutrition.sodium)) / \(Int(sodiumLimit)) mg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sodiumColor)
                }
                ProgressView(value: min(viewModel.nutrition.sodium, sodiumLimit), total: sodiumLimit)
                    .tint(sodiumColor)
                Text(sodiumStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private var sodiumColor: Color {
        let ratio = viewModel.nutrition.sodium / sodiumLimit
        if ratio > 1 { return .red }
        if ratio >= 0.8 { return .orange }
        return .green
    }

    private var sodiumStatus: String {
        let remaining = sodiumLimit - viewModel.nutrition.sodium
        if remaining >= 0 {
            return "\(Int(remaining)) mg sodium remaining today"
        }
        return "\(Int(abs(remaining))) mg over today's sodium limit"
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

    private var checklistCard: some View {
        DailyChecklistCard(
            items: checklistItems,
            faceCheckedInToday: faceCheckedInToday,
            sessionsDueToday: sessionsDueToday,
            completedWorkouts: completedWorkouts,
            onStartSession: { session in
                actionTick += 1
                activeWorkout = WorkoutScheduleGeneratorService.workout(
                    for: session, existingWorkouts: allWorkouts, context: context)
            })
    }

    private var looksCard: some View {
        NavigationLink(destination: LooksDashboardView()) {
            DashboardCard(title: "Looks", systemImage: "sparkles") {
                HStack {
                    StatChip(label: "Overall",
                             value: overallLooksScore.map { "\(Int($0))" } ?? "N/A")
                    StatChip(label: "Face",
                             value: latestFaceCheckIn.map { "\(Int($0.totalScore))" } ?? "N/A")
                    StatChip(label: "Body",
                             value: displayedBodyScore.map { "\(Int($0))" } ?? "N/A")
                }
                HStack {
                    StatChip(label: "Streak",
                             value: appearanceStreak > 0 ? "\(appearanceStreak)d" : "N/A")
                    StatChip(label: "Suggestions",
                             value: "\(pendingSuggestionCount)",
                             color: pendingSuggestionCount > 0 ? .orange : .primary)
                }
                if latestBodyCheckIn == nil, liveBodyScore != nil {
                    Text("Body score estimated from your logged weight and body fat. Add a body photo check-in for the full picture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if appearanceCheckIns.isEmpty {
                    Text("Track face and body scores from daily photos and your existing body data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.pressable)
    }

    private var appearanceStreak: Int {
        AppearanceScoringService.faceStreak(history: appearanceCheckIns)
    }

    private var trendCard: some View {
        DashboardCard(title: "Trends", systemImage: "chart.line.uptrend.xyaxis") {
            HStack {
                let latest = WeightTrendCalculator.latestKg(entries: weights)
                StatChip(label: "Current weight", value: latest.map { Formatters.kg($0) } ?? "Log weight")
                StatChip(label: "7-day calories", value: viewModel.weeklyCalorieAverage.map { "\(Int($0))" } ?? "No meals")
                StatChip(label: "Adherence", value: adherenceLabel)
            }
            NavigationLink(destination: WeightTrendsView()) {
                Label("View weight trends", systemImage: "chart.line.uptrend.xyaxis")
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
                    let latest = WeightTrendCalculator.latestKg(entries: weights)
                    StatChip(label: "Current weight", value: latest.map { Formatters.kg($0) } ?? "No data")
                    StatChip(label: "Target", value: Formatters.kg(goal.targetWeightKg))
                    let rate = WeightTrendCalculator.weeklyChangeFromEntries(entries: weights)
                    StatChip(label: "Per week", value: rate.map { Formatters.kgChange($0) } ?? "Not enough data",
                             color: rateColor(rate, goal: goal))
                }
            }
        }
        .buttonStyle(.pressable)
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
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    private func createBlankWorkout() {
        let workout = Workout(date: .now, title: "Workout", type: .custom)
        context.insert(workout)
        activeWorkout = workout
    }
}
