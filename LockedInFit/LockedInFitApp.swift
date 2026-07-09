import SwiftUI
import SwiftData

@main
struct LockedInFitApp: App {
    let container: ModelContainer

    init() {
        // From here on, any main-thread stall longer than a second gets
        // logged from a background watchdog while it's happening, even if
        // the stalled call itself was never instrumented and never returns.
        MainThreadHangDetector.shared.start()

        // Resolve the shared App Group container immediately (background
        // queue, non-blocking, duration logged). Backup mirrors are written
        // there so they survive the container wipes that updates can cause,
        // and the restore pickers need it resolved to SHOW those mirrors —
        // including on the very first launch after such a wipe.
        AppGroupContainerLocator.beginResolvingContainer()

        // Byte-for-byte safety net, before SwiftData gets a chance to open
        // (and possibly migrate) the store. See PersistenceGuard.
        PerfLog.measure("launch.persistenceGuard") { PersistenceGuard.runPreLaunchChecks() }

        // Migration policy: this list only ever grows additively (new
        // @Model types, or a new property on an existing one with a default
        // value) so SwiftData's automatic lightweight migration applies.
        // Never remove/rename a persisted type or property, and never add a
        // ModelConfiguration with a destructive migration option, without an
        // explicit, user-confirmed migration path first (see
        // PersistenceGuard, BackupService, and DataLossGuard, all of which
        // exist because a signing/App Group change once wiped local data
        // without any of this in place).
        do {
            container = try PerfLog.measure("launch.modelContainer") {
                try ModelContainer(for:
                    MealLog.self, FoodItem.self, FoodPreset.self,
                    BodyWeightEntry.self, BodyFatEntry.self, MeasurementEntry.self,
                    ProgressPhoto.self, StepEntry.self, ActiveEnergyEntry.self, Goal.self,
                    Workout.self, Exercise.self, WorkoutSet.self,
                    StrengthScore.self, UserSettings.self, HealthScan.self,
                    AppearanceCheckIn.self, AppearanceSuggestion.self, DailyChecklistItem.self,
                    WorkoutSchedule.self, WorkoutScheduleSession.self, CalendarConnectionState.self,
                    SleepLog.self, NapLog.self)
            }
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        PerfLog.measure("launch.seed") {
            SeedDataService.seedIfNeeded(context: container.mainContext)
            SeedDataService.clearEmptyWorkoutsIfNeeded(context: container.mainContext)
        }
        // Sleep score repair runs synchronously on the main context, and
        // that's deliberate. A version briefly ran it on a background
        // @ModelActor context, but background-context WRITES are the one
        // SwiftData pattern this app has actually seen deadlock in the
        // wild (the main thread's next store access hangs permanently
        // right after a background save — confirmed twice by the hang
        // watchdog before all cross-context writes were removed). The
        // PerfLog line proves this costs single-digit-to-low-double-digit
        // milliseconds at launch; if sleep history ever grows enough for
        // this to show up as a SLOW MAIN THREAD fault in the log, bound
        // the repair, don't move it off-main.
        PerfLog.measure("launch.sleepRepair") {
            SleepScoringService.repairAll(
                logs: (try? container.mainContext.fetch(FetchDescriptor<SleepLog>())) ?? [],
                naps: (try? container.mainContext.fetch(FetchDescriptor<NapLog>())) ?? [])
        }
        HealthKitManager.shared.configureAutoSync(container: container)
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
        // Backgrounding is the moment right before an app update — the exact
        // event local backups exist to survive — so capture the latest state
        // here. Unlike an earlier design that ran the whole JSON snapshot
        // synchronously on the main thread (and blocked resigning active),
        // this does a cheap main-context save so the snapshot sees the last
        // few seconds of edits, then fires a detached background backup and
        // returns immediately. The content-hash dedupe inside performBackup
        // makes ordinary app switching with no changes a no-op.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            try? container.mainContext.save()
            BackupService.backupOnBackgrounding(container: container)
        }
    }
}

struct RootTabView: View {
    private enum Tab: Hashable { case today, log, train, looks, trends }

    @Environment(\.modelContext) private var context
    @State private var selection: Tab = .today
    // Each tab owns its own navigation stack so tabs never share nested state.
    @State private var todayPath = NavigationPath()
    @State private var logPath = NavigationPath()
    @State private var trainPath = NavigationPath()
    @State private var looksPath = NavigationPath()
    @State private var trendsPath = NavigationPath()
    /// nil until the first-launch data-loss check has run, so the normal tab
    /// UI never flashes before that check has a chance to redirect to
    /// recovery. See DataLossGuard.
    @State private var dataLossDetected: Bool?

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
        Group {
            switch dataLossDetected {
            case .some(true):
                DataRecoveryView(onResolved: { dataLossDetected = false })
            case .some(false):
                mainTabs
            case .none:
                Color.clear
            }
        }
        .onAppear {
            guard dataLossDetected == nil else { return }
            let lostData = PerfLog.measure("launch.dataLossCheck") {
                DataLossGuard.checkForSuddenDataLoss(context: context)
            }
            dataLossDetected = lostData
            // No backup scheduled here: launch is not a data-mutation event.
            // Automatic backups only run after something actually changes
            // (see BackupService.scheduleBackupSoon call sites).
        }
        // Belt-and-suspenders safety net, independent of any per-screen
        // onChange wiring. DashboardView's onChange triggers only cover the
        // handful of @Query properties it happens to watch (meals, workouts,
        // steps, sleep, weight...) — editing a measurement, a progress
        // photo, a food preset, a health scan, or a workout schedule never
        // touches any of those, so a change made anywhere else could sit
        // unbacked-up for however long the app stays open. Pinging every 60s
        // guarantees SOME trigger lands inside every 5-minute throttle
        // window regardless of which screen/model was actually edited — and
        // it's cheap: scheduleBackupSoon's own throttle still caps real
        // writes to once per 5 minutes, and the content-hash dedupe in
        // performBackup makes a no-change tick free. Same loop also samples
        // the record count so a mid-session drop gets logged the moment it
        // happens instead of only being discoverable on the next launch.
        .task {
            // No gate on dataLossDetected here (its ordering relative to
            // onAppear isn't guaranteed): harmless either way, since
            // performBackup already refuses to write an empty snapshot over
            // an existing non-empty backup.
            var lastSampledCount = DataLossGuard.currentRecordCount(context: context)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                lastSampledCount = DataLossGuard.watchForMidSessionLoss(context: context, previousCount: lastSampledCount)
                BackupService.scheduleBackupSoon(container: context.container)
            }
        }
    }

    private var mainTabs: some View {
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

// Shared, file-scope fetch descriptors; see the comment in
// DashboardView.swift for why these must never be rebuilt per view init.
private let trendsActiveGoals = FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.active })
private let trendsMeals = FetchDescriptor<MealLog>(sortBy: [SortDescriptor(\MealLog.date, order: .reverse)])
private let trendsCompletedWorkouts = FetchDescriptor<Workout>(
    predicate: #Predicate<Workout> { $0.completed && !$0.isTemplate },
    sortBy: [SortDescriptor(\Workout.date, order: .reverse)])
private let trendsAppearanceCheckIns = FetchDescriptor<AppearanceCheckIn>(sortBy: [SortDescriptor(\AppearanceCheckIn.date, order: .reverse)])

/// Trends hub: weekly, weight, goal, body data. The "This Week" summary is
/// where nutrition, training, appearance, and suggestions converge into one
/// view: trends isn't just weight charts, it's the whole system's readout.
struct TrendsHomeView: View {
    @Query(trendsActiveGoals) private var activeGoals: [Goal]
    @Query(trendsMeals) private var meals: [MealLog]
    @Query(trendsCompletedWorkouts) private var completedWorkouts: [Workout]
    @Query(trendsAppearanceCheckIns) private var appearanceCheckIns: [AppearanceCheckIn]
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
