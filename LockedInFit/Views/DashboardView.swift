import SwiftUI
import SwiftData
import Charts

// Fetch descriptors are built ONCE at file scope and shared by the @Query
// properties below, never rebuilt per view init. This is load-bearing: a
// debugger pause during the long-standing "Settings freezes" bug showed the
// main thread livelocked inside an AttributeGraph update comparing @Query
// configurations (Array<SortDescriptor>.== -> AnySortComparator.==, each
// comparison instantiating generic metadata). Inline `sort:`/`filter:`
// arguments create fresh descriptor/key-path/comparator instances on every
// view re-init, forcing SwiftUI to deep-compare them on every graph update;
// one shared instance per descriptor makes that comparison trivially stable.
// The same pattern applies in every view on the affected navigation chain.
private let dashboardActiveGoals = FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.active })
private let dashboardMeals = FetchDescriptor<MealLog>(sortBy: [SortDescriptor(\MealLog.date, order: .reverse)])
private let dashboardWeights = FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\BodyWeightEntry.date)])
private let dashboardBodyFats = FetchDescriptor<BodyFatEntry>(sortBy: [SortDescriptor(\BodyFatEntry.date)])
private let dashboardSteps = FetchDescriptor<StepEntry>(sortBy: [SortDescriptor(\StepEntry.date, order: .reverse)])
private let dashboardActiveEnergy = FetchDescriptor<ActiveEnergyEntry>(sortBy: [SortDescriptor(\ActiveEnergyEntry.date, order: .reverse)])
private let dashboardCompletedWorkouts = FetchDescriptor<Workout>(
    predicate: #Predicate<Workout> { $0.completed && !$0.isTemplate },
    sortBy: [SortDescriptor(\Workout.date, order: .reverse)])
private let dashboardAllWorkouts = FetchDescriptor<Workout>(
    predicate: #Predicate<Workout> { !$0.isTemplate },
    sortBy: [SortDescriptor(\Workout.date, order: .reverse)])
private let dashboardAppearanceCheckIns = FetchDescriptor<AppearanceCheckIn>(sortBy: [SortDescriptor(\AppearanceCheckIn.date, order: .reverse)])
private let dashboardSleepLogs = FetchDescriptor<SleepLog>(sortBy: [
    SortDescriptor(\SleepLog.date, order: .reverse),
    SortDescriptor(\SleepLog.createdAt, order: .reverse),
])

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(dashboardActiveGoals) private var activeGoals: [Goal]
    @Query(dashboardMeals) private var meals: [MealLog]
    @Query(dashboardWeights) private var weights: [BodyWeightEntry]
    @Query(dashboardBodyFats) private var bodyFats: [BodyFatEntry]
    @Query(dashboardSteps) private var steps: [StepEntry]
    @Query(dashboardActiveEnergy) private var activeEnergy: [ActiveEnergyEntry]
    @Query(dashboardCompletedWorkouts) private var completedWorkouts: [Workout]
    @Query(dashboardAllWorkouts) private var allWorkouts: [Workout]
    @Query private var strengthScores: [StrengthScore]
    @Query(dashboardAppearanceCheckIns) private var appearanceCheckIns: [AppearanceCheckIn]
    @Query private var appearanceSuggestions: [AppearanceSuggestion]
    @Query private var checklistItems: [DailyChecklistItem]
    @Query private var workoutSchedules: [WorkoutSchedule]
    @Query(dashboardSleepLogs) private var sleepLogs: [SleepLog]

    @State private var showAddMeal = false
    @State private var showPhotoAnalysis = false
    @State private var showLogWeight = false
    @State private var newWeight = ""
    @State private var healthKit = HealthKitManager.shared
    @State private var activeWorkout: Workout?
    /// True when `activeWorkout` was just created via createBlankWorkout()
    /// and hasn't been saved yet — see WorkoutLogView's Cancel/Save toolbar.
    @State private var activeWorkoutIsDraft = false
    @State private var actionTick = 0
    @State private var showCalorieDetails = false

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
    private var loggedMealTypesToday: Set<MealType> { Set(todayMeals.map(\.mealType)) }

    private var dueChecklistItemsToday: [DailyChecklistItem] { DailyChecklistService.dueItems(checklistItems) }
    private var openChecklistItemsExcludingSleep: [DailyChecklistItem] {
        DailyChecklistService.openItemsExcludingSleep(checklistItems)
    }
    private var sleepItemDueIncomplete: Bool {
        DailyChecklistService.sleepItemDueIncomplete(checklistItems)
    }
    /// Whether the user has actually used the sleep-logging flow today,
    /// independent of whether any checklist item happens to be checked off.
    private var sleepLoggedToday: Bool {
        sleepLogs.contains { $0.createdAt.isToday }
    }
    private var sleepChecklistItemsDueToday: [DailyChecklistItem] {
        dueChecklistItemsToday.filter { $0.category == .sleep }
    }
    /// Once real sleep tracking is in use, "sleep goal hit" means today's
    /// night was actually logged: that's the real signal now available.
    /// Falls back to the sleep-category checklist proxy for anyone who
    /// hasn't logged a night yet, so the achievement still means something
    /// either way instead of going silent.
    private var sleepGoalHitToday: Bool {
        if !sleepLogs.isEmpty {
            return sleepLogs.contains { $0.date.isToday }
        }
        return !sleepChecklistItemsDueToday.isEmpty && sleepChecklistItemsDueToday.allSatisfy { DailyChecklistService.isCompleted($0) }
    }
    /// Only counts as "complete" when there's an actual looks/body/face
    /// checklist item beyond the mandatory face photo, otherwise this would
    /// fire every single day just for taking the daily face photo.
    private var looksChecklistCompleteToday: Bool {
        let looksItems = dueChecklistItemsToday.filter { [.looks, .body, .face].contains($0.category) }
        return faceCheckedInToday && !looksItems.isEmpty && looksItems.allSatisfy { DailyChecklistService.isCompleted($0) }
    }

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
    private var latestSleepLog: SleepLog? { sleepLogs.first }
    private var sleepStreak: Int { SleepScoringService.streak(history: sleepLogs) }
    private var sleepAverageTimes: (bedtime: String?, wake: String?) {
        let distinct = SleepScoringService.distinctNights(sleepLogs)
        return SleepScoringService.averageTimes(for: Array(distinct.prefix(7)))
    }

    private var maintenance: Double {
        guard let settings else { return 2400 }
        return Analytics.estimateMaintenance(settings: settings, weights: weights, meals: meals, steps: steps)
    }

    private var calorieTarget: Double { goal?.calorieTarget ?? maintenance }
    private var proteinTarget: Double { goal?.proteinTarget ?? 140 }
    private var sodiumLimit: Double { max(1, settings?.sodiumLimitMg ?? 2300) }

    var body: some View {
        dashboardCore
            .sheet(isPresented: $showAddMeal) { AddMealView() }
            .sheet(isPresented: $showPhotoAnalysis) { MealPhotoAnalysisView() }
            .sheet(item: $activeWorkout) { workout in
                NavigationStack { WorkoutLogView(workout: workout, isDraft: activeWorkoutIsDraft) }
            }
            .alert("Log Weigh-In", isPresented: $showLogWeight) {
                TextField("Weight (kg)", text: $newWeight)
                    .keyboardType(.decimalPad)
                Button("Save") { saveWeight() }
                Button("Cancel", role: .cancel) {}
            }
            .sensoryFeedback(.selection, trigger: actionTick)
    }

    /// Split into staged sub-expressions (`dashboardWithTriggers` →
    /// `dashboardCore`, plus the destination switch as its own function) so
    /// the compiler never has to type-check the whole modifier chain as one
    /// expression — the single-expression combination is what repeatedly
    /// blows past its time limit as triggers get added.
    private var dashboardCore: some View {
        dashboardWithTriggers
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: SettingsRoute.settings) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            // Lazy, value-based destinations for the whole Settings area.
            // Each screen is constructed exactly once when its route is
            // pushed — never stored inside a NavigationLink value, never
            // rebuilt by toolbar/navigation re-resolution. See SettingsRoute
            // for the update-cycle bug this exists to prevent.
            .navigationDestination(for: SettingsRoute.self) { route in
                settingsDestination(for: route)
            }
    }

    /// The scroll view plus its data-change triggers (reminder refresh and
    /// backup scheduling), type-checked separately from the navigation
    /// chrome above.
    private var dashboardWithTriggers: some View {
        dashboardScrollView
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await healthKit.sync(context: context)
                await refreshReminderSchedules()
            }
            .task { await refreshReminderSchedules() }
            .onChange(of: meals) { _, _ in triggerReminderRefresh(); scheduleBackup() }
            .onChange(of: completedWorkouts) { _, _ in triggerReminderRefresh(); scheduleBackup() }
            .onChange(of: checklistItems) { _, _ in triggerReminderRefresh(); scheduleBackup() }
            .onChange(of: steps) { _, _ in triggerReminderRefresh(); scheduleBackup() }
            .onChange(of: appearanceCheckIns) { _, _ in triggerReminderRefresh(); scheduleBackup() }
            .onChange(of: sleepLogs) { _, _ in triggerReminderRefresh(); scheduleBackup() }
            .onChange(of: weights) { _, _ in scheduleBackup() }
            .onChange(of: bodyFats) { _, _ in scheduleBackup() }
    }

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .settings: SettingsView()
        case .goalEdit: GoalEditView()
        case .notifications: NotificationSettingsView()
        case .aiSettings: AISettingsView()
        case .healthKitSync: HealthKitSyncView()
        case .looksSettings: LooksSettingsView()
        case .socialClimber: SocialClimberLinkView()
        case .googleCalendar: GoogleCalendarConnectView()
        case .backups: BackupRestoreListView()
        case .diagnostics:
            #if DEBUG
            DiagnosticsView()
            #else
            EmptyView()
            #endif
        }
    }

    private func triggerReminderRefresh() {
        Task { await refreshReminderSchedules() }
    }

    /// Backup scheduling is deliberately its own trigger, separate from
    /// reminder refresh: reminder scheduling can run for reasons that have
    /// nothing to do with data changing (notification settings, timing
    /// windows), and bundling a backup into it meant routine refreshes were
    /// scheduling backups too. This only fires from actual data-mutation
    /// signals (the onChange triggers above). Fully non-blocking: hands off
    /// to BackupService's own debounce/throttle, off the main thread.
    private func scheduleBackup() {
        BackupService.scheduleBackupSoon(container: context.container)
    }

    private var dashboardScrollView: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                quickActions
                checklistCard
                socialReadinessCardIfPresent
                calorieCard
                macroCard
                activityCard
                looksCard
                sleepCard
                trendCard
                goalSnippetIfPresent
                mealsCard
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var goalSnippetIfPresent: some View {
        if let goal {
            goalSnippet(goal)
        }
    }

    /// Settings → Social Climber kill switch for the whole bridge, in both
    /// directions. Defaults to on since the bridge is already fail-safe, but
    /// this is the explicit off switch for keeping LockedInFit fully
    /// self-contained.
    private var crossAppSharingEnabled: Bool { settings?.crossAppSharingEnabled ?? true }

    /// Fresh (non-stale) Social Climber event context, reduced to what the
    /// dashboard and checklist need. Reading is a cheap local file check and
    /// nil the vast majority of the time (sharing off, no App Group, no
    /// Social Climber, or no notable event), so it's safe to recompute on
    /// each render.
    private var socialReadiness: CrossAppIntegrationManager.SocialReadiness? {
        guard crossAppSharingEnabled else { return nil }
        return CrossAppIntegrationManager.socialReadiness(from: CrossAppIntegrationManager.readSocialContext())
    }

    @ViewBuilder
    private var socialReadinessCardIfPresent: some View {
        if let socialReadiness {
            SocialReadinessCard(readiness: socialReadiness)
        }
    }

    /// Keep the rolling reminder windows topped up and re-check dietary/goal
    /// events. Never prompts for permission; NotificationService skips
    /// scheduling if not authorized. Runs on appear and whenever today's
    /// logs change, so it survives normal navigation and data updates.
    ///
    /// @MainActor explicitly (not left to SDK inference): this reads
    /// main-context models (settings, schedules, meals, checklist) between
    /// awaits, and as a nonisolated async method it would run on a
    /// background executor — cross-thread model access that can deadlock
    /// the store against whatever the main thread is fetching.
    @MainActor
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
        await NotificationService.refreshMealReminders(
            enabled: settings.mealReminderEnabled,
            loggedMealTypesToday: loggedMealTypesToday)
        await NotificationService.refreshSleepReminder(
            enabled: settings.sleepReminderEnabled,
            hour: settings.sleepReminderHour,
            minute: settings.sleepReminderMinute,
            dueAndIncomplete: sleepItemDueIncomplete,
            sleepLoggedToday: sleepLoggedToday)
        await NotificationService.refreshChecklistDigest(
            enabled: settings.checklistReminderEnabled,
            hour: 18, minute: 0,
            openCount: openChecklistItemsExcludingSleep.count)

        await evaluateNotificationEvents(settings: settings)
        syncCrossAppContext()
    }

    /// Optional cross-app bridge: publishes a small public snapshot for
    /// Social Climber to read, and turns any fresh Social Climber event
    /// context into ordinary checklist items owned by LockedInFit. Entirely
    /// a no-op if the shared App Group container isn't available or Social
    /// Climber's context is missing, stale, or corrupt. See
    /// CrossAppIntegrationManager.
    private func syncCrossAppContext() {
        guard crossAppSharingEnabled else { return }
        CrossAppIntegrationManager.publish(crossAppPublishInput)
        guard let socialReadiness else { return }
        EventAwareChecklistService.generateItems(
            readiness: socialReadiness,
            workoutPlannedToday: workoutPlannedToday,
            existing: checklistItems,
            context: context)
    }

    private var workoutPlannedToday: Bool {
        !sessionsDueToday.isEmpty || dueChecklistItemsToday.contains { $0.category == .workout }
    }

    private var crossAppPublishInput: CrossAppIntegrationManager.PublishInput {
        let dueToday = DailyChecklistService.dueItems(checklistItems)
        let dueIncomplete = dueToday.filter { !DailyChecklistService.isCompleted($0) }
        let importantTasks = dueIncomplete.map { item in
            CrossAppIntegrationManager.ImportantTaskInput(
                id: item.uuid,
                title: item.title,
                category: Self.publicTaskCategory(for: item.category),
                overdue: item.recurrence == .none && item.dueDate.startOfDay < Date().startOfDay)
        }
        let completionRatio = dueToday.isEmpty ? 1.0
            : Double(dueToday.count - dueIncomplete.count) / Double(dueToday.count)
        return CrossAppIntegrationManager.PublishInput(
            sleepScore: latestSleepLog?.totalScore,
            workoutPlannedToday: workoutPlannedToday,
            workoutCompletedToday: viewModel.completedWorkoutsToday > 0,
            nutritionEatenCalories: viewModel.calories.eaten,
            nutritionTargetCalories: viewModel.calories.adjustedTarget,
            hasLoggedFoodToday: !todayMeals.isEmpty,
            dailyChecklistCompletion: completionRatio,
            importantTasks: importantTasks)
    }

    private static func publicTaskCategory(for category: ChecklistCategory) -> LockedInFitPublicContext.HealthTaskCategory {
        switch category {
        case .sleep: return .sleep
        case .nutrition: return .meal
        case .workout: return .workout
        case .looks, .body, .face: return .appearance
        case .manual: return .general
        }
    }

    /// Shared with the checklist's dietary-watch banner below, so the push
    /// alert and the on-screen warning are always computed from the same numbers.
    private var notificationInputs: NotificationRulesEngine.Inputs {
        NotificationRulesEngine.Inputs(
            nutrition: viewModel.nutrition,
            eaten: viewModel.calories.eaten,
            calorieTarget: calorieTarget,
            adjustedCalorieTarget: viewModel.calories.adjustedTarget,
            proteinTarget: proteinTarget,
            sodiumLimit: sodiumLimit,
            stepsToday: viewModel.stepsToday,
            stepTarget: viewModel.stepTarget,
            completedWorkoutsToday: viewModel.completedWorkoutsToday,
            now: .now)
    }

    /// Dietary-limit and goal-achievement alerts fire immediately when
    /// crossed, but NotificationService.fireOnce ensures each one only
    /// reaches the user once per day.
    @MainActor
    private func evaluateNotificationEvents(settings: UserSettings) async {
        let input = notificationInputs
        var events: [NotificationService.NotificationEvent] = []
        if settings.dietaryLimitAlertsEnabled {
            events += NotificationRulesEngine.dietaryEvents(input)
        }
        if settings.goalAlertsEnabled {
            events += NotificationRulesEngine.goalEvents(
                input, sleepGoalHit: sleepGoalHitToday, looksChecklistComplete: looksChecklistCompleteToday)
        }
        await NotificationService.fireOnce(events, settings: settings)
    }

    /// Same dietary events as the push notifications, shown inline on
    /// Today's Checklist so limits are visible where the user is already
    /// looking, not just in an alert that already fired. Guarded the same
    /// way as evaluateNotificationEvents (no settings row yet → neither
    /// surface fires) so the two never disagree.
    private var dietaryWatchLines: [String] {
        guard let settings, settings.dietaryLimitAlertsEnabled else { return [] }
        return NotificationRulesEngine.dietaryEvents(notificationInputs).map { "\($0.title): \($0.body)" }
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
                    scoreRow("Calories", done: viewModel.calories.eaten > 0 && abs(viewModel.calories.eaten - viewModel.calories.adjustedTarget) / max(viewModel.calories.adjustedTarget, 1) < 0.15)
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
                Task {
                    await healthKit.sync(context: context)
                    await refreshReminderSchedules()
                }
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
                ProgressView(value: min(viewModel.calories.eaten, viewModel.calories.adjustedTarget), total: max(viewModel.calories.adjustedTarget, 1))
                    .tint(viewModel.calories.eaten > viewModel.calories.adjustedTarget ? .red : .accentColor)
                HStack {
                    StatChip(label: "Eaten", value: "\(Int(viewModel.calories.eaten))")
                    StatChip(label: "Base", value: "\(Int(viewModel.calories.baseTarget))")
                    StatChip(label: "Target", value: "\(Int(viewModel.calories.adjustedTarget))")
                }
                HStack {
                    StatChip(label: "Exercise", value: "+\(Int(viewModel.calories.exerciseAdjustment))")
                    StatChip(label: "TEF", value: "+\(Int(viewModel.calories.tefCalories))", color: .purple)
                    StatChip(label: "Oil", value: "+\(Int(viewModel.calories.hiddenOilCalories))", color: .orange)
                }
                Button {
                    withAnimation(.snappy) { showCalorieDetails.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showCalorieDetails ? "Hide details" : "Why this target?")
                        Image(systemName: showCalorieDetails ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if showCalorieDetails {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(adjustmentLabel, systemImage: viewModel.activity.isEstimated ? "waveform.path.ecg" : "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if viewModel.calories.tefCalories > 0 {
                            Label("TEF adds +\(Int(viewModel.calories.tefCalories)) kcal to today's target from digesting what you've already eaten.", systemImage: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        }
                        if viewModel.nutrition.hiddenOilHigh > 0 {
                            Label("Hidden oil adds +\(Int(viewModel.calories.hiddenOilCalories)) kcal to eaten (range +\(Int(viewModel.nutrition.hiddenOilLow))–\(Int(viewModel.nutrition.hiddenOilHigh)))", systemImage: "drop.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Text("Estimated maintenance: \(Int(maintenance)) kcal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
        if ratio >= NotificationRulesEngine.exceededRatio { return .red }
        if ratio >= NotificationRulesEngine.sodiumApproachingRatio { return .orange }
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
                activeWorkoutIsDraft = false
                activeWorkout = WorkoutScheduleGeneratorService.workout(
                    for: session, existingWorkouts: allWorkouts, context: context)
            },
            onToggle: { Task { await refreshReminderSchedules() } },
            dietaryWatchLines: dietaryWatchLines)
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

    private var sleepCard: some View {
        NavigationLink(destination: SleepDashboardView()) {
            DashboardCard(title: "Sleep", systemImage: "bed.double.fill") {
                HStack {
                    StatChip(label: "Score", value: latestSleepLog.map { "\(Int($0.totalScore))" } ?? "N/A")
                    StatChip(label: "Duration", value: latestSleepLog.map { "\(Formatters.trimmed($0.durationHours))h" } ?? "N/A")
                    StatChip(label: "Wake-ups", value: latestSleepLog.map { "\($0.wakeUps)" } ?? "N/A")
                }
                HStack {
                    StatChip(label: "Streak", value: sleepStreak > 0 ? "\(sleepStreak)d" : "N/A")
                }
                if sleepLogs.isEmpty {
                    Text("Log your bedtime and wake time to start tracking your sleep score.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SleepTimesTable(bedtime: sleepAverageTimes.bedtime, wake: sleepAverageTimes.wake)
                }
            }
        }
        .buttonStyle(.pressable)
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
        guard viewModel.calories.eaten > 0 else { return "No logs" }
        let deviation = abs(viewModel.calories.eaten - viewModel.calories.adjustedTarget) / max(viewModel.calories.adjustedTarget, 1)
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
        // Not inserted here — only Save/Finish in WorkoutLogView commits a
        // blank workout to the store, so backing out via Cancel never
        // leaves a stray entry in history.
        activeWorkoutIsDraft = true
        activeWorkout = Workout(date: .now, title: "Workout", type: .custom)
    }
}
