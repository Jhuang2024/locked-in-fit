import SwiftUI
import SwiftData
import UserNotifications

// Shared, file-scope fetch descriptors; see the comment in
// DashboardView.swift for why these must never be rebuilt per view init.
private let notificationsMeals = FetchDescriptor<MealLog>(sortBy: [SortDescriptor(\MealLog.date, order: .reverse)])
private let notificationsCheckIns = FetchDescriptor<AppearanceCheckIn>(sortBy: [SortDescriptor(\AppearanceCheckIn.date, order: .reverse)])

/// Single control surface for every notification category: what fires,
/// whether it's on, and a quick status/next-reminder readout. Detailed
/// scheduling (time of day, body-photo frequency, workout lead time) stays
/// in Looks & Calendar: this is the at-a-glance switchboard.
struct NotificationSettingsView: View {
    @Query private var settingsList: [UserSettings]
    @Query private var checklistItems: [DailyChecklistItem]
    @Query(notificationsMeals) private var meals: [MealLog]
    @Query(notificationsCheckIns) private var appearanceCheckIns: [AppearanceCheckIn]
    @Query private var workoutSchedules: [WorkoutSchedule]

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var nextReminder: Date?

    private var settings: UserSettings? { settingsList.first }

    private var faceCheckedInToday: Bool {
        appearanceCheckIns.contains { $0.kind == .face && $0.date.isToday }
    }
    private var loggedMealTypesToday: Set<MealType> {
        Set(meals.filter { $0.date.isToday }.map(\.mealType))
    }
    private var sleepItemDueIncomplete: Bool {
        DailyChecklistService.sleepItemDueIncomplete(checklistItems)
    }
    private var openChecklistCountExcludingSleep: Int {
        DailyChecklistService.openItemsExcludingSleep(checklistItems).count
    }

    var body: some View {
        let _ = PerfLog.tick("NotificationSettingsView.body")
        Form {
            statusSection
            if let settings {
                remindersSection(settings)
                alertsSection(settings)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { PerfLog.event("nav.notifications.appear") }
        .task { await refreshStatus() }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: authorizationStatus == .authorized ? "checkmark.circle.fill" : "bell.slash")
                    .foregroundStyle(authorizationStatus == .authorized ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLabel)
                        .font(.subheadline.weight(.medium))
                    if let nextReminder {
                        Text("Next reminder \(nextReminder.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            if authorizationStatus == .denied {
                Text("Notifications are off for Locked In Fit in iOS Settings. Enable them there to use reminders.")
            }
        }
    }

    private var statusLabel: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Reminders enabled"
        case .denied: return "Reminders off in iOS Settings"
        default: return "Reminders not yet enabled"
        }
    }

    // MARK: - Reminders (scheduled ahead of time)

    private func remindersSection(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            categoryToggle("Meals", systemImage: "fork.knife", isOn: Binding(
                get: { settings.mealReminderEnabled },
                set: { on in
                    settings.mealReminderEnabled = on
                    apply(on, turnOff: { settings.mealReminderEnabled = false }) {
                        await NotificationService.refreshMealReminders(enabled: on, loggedMealTypesToday: loggedMealTypesToday)
                    }
                }))
            categoryToggle("Sleep", systemImage: "moon.zzz", isOn: Binding(
                get: { settings.sleepReminderEnabled },
                set: { on in
                    settings.sleepReminderEnabled = on
                    apply(on, turnOff: { settings.sleepReminderEnabled = false }) {
                        await NotificationService.refreshSleepReminder(
                            enabled: on, hour: settings.sleepReminderHour, minute: settings.sleepReminderMinute,
                            dueAndIncomplete: sleepItemDueIncomplete)
                    }
                }))
            categoryToggle("Face scan", systemImage: "face.smiling", isOn: Binding(
                get: { settings.faceReminderEnabled },
                set: { on in
                    settings.faceReminderEnabled = on
                    apply(on, turnOff: { settings.faceReminderEnabled = false }) {
                        await NotificationService.refreshFaceReminders(
                            enabled: on, hour: settings.faceReminderHour, minute: settings.faceReminderMinute,
                            faceCheckedInToday: faceCheckedInToday)
                    }
                }))
            categoryToggle("Workouts", systemImage: "dumbbell", isOn: Binding(
                get: { settings.workoutRemindersEnabled },
                set: { on in
                    settings.workoutRemindersEnabled = on
                    apply(on, turnOff: { settings.workoutRemindersEnabled = false }) {
                        for schedule in workoutSchedules where schedule.isActive {
                            await NotificationService.refreshWorkoutReminders(
                                schedule: schedule, enabled: on, offsetMinutes: settings.defaultWorkoutReminderMinutes)
                        }
                    }
                }))
            categoryToggle("Checklist reminders", systemImage: "checklist", isOn: Binding(
                get: { settings.checklistReminderEnabled },
                set: { on in
                    settings.checklistReminderEnabled = on
                    apply(on, turnOff: { settings.checklistReminderEnabled = false }) {
                        await NotificationService.refreshChecklistDigest(
                            enabled: on, hour: 18, minute: 0, openCount: openChecklistCountExcludingSleep)
                    }
                }))
        } header: {
            Text("Reminders")
        } footer: {
            Text("Tied to what's actually due today: an already-completed item never nags. Face scan time and workout lead time are in Looks & Calendar.")
        }
    }

    // MARK: - Alerts (fire when a threshold is crossed)

    private func alertsSection(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            categoryToggle("Dietary limits", systemImage: "exclamationmark.triangle", isOn: Binding(
                get: { settings.dietaryLimitAlertsEnabled },
                set: { on in
                    settings.dietaryLimitAlertsEnabled = on
                    apply(on, turnOff: { settings.dietaryLimitAlertsEnabled = false }) {}
                }))
            categoryToggle("Goal achievements", systemImage: "trophy", isOn: Binding(
                get: { settings.goalAlertsEnabled },
                set: { on in
                    settings.goalAlertsEnabled = on
                    apply(on, turnOff: { settings.goalAlertsEnabled = false }) {}
                }))
        } header: {
            Text("Alerts")
        } footer: {
            Text("Calories, sodium, and fat alert once when approaching and once when over. Protein, steps, workouts, and sleep alert once when hit.")
        }
    }

    private func categoryToggle(_ label: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        // Instrumented wrapper: if SwiftUI ends up in a toggle-binding
        // read loop (a debugger pause during the freeze showed
        // Switch.updateUIView -> ToggleState.stateFor -> binding reads),
        // the tick log names this screen's toggles as the cycling party.
        let counted = Binding(
            get: {
                PerfLog.tick("NotificationSettings.toggle.get")
                return isOn.wrappedValue
            },
            set: { isOn.wrappedValue = $0 })
        return Toggle(isOn: counted) {
            Label(label, systemImage: systemImage)
        }
    }

    // MARK: - Helpers

    /// Requests authorization the first time a category is switched on
    /// (turning the toggle back off if the user declines), then runs the
    /// category's own refresh so the change takes effect immediately.
    private func apply(_ enabling: Bool, turnOff: @escaping () -> Void, refresh: @escaping () async -> Void) {
        Task {
            if enabling {
                let granted = await NotificationService.ensureAuthorization()
                guard granted else {
                    turnOff()
                    await refreshStatus()
                    return
                }
            }
            await refresh()
            await refreshStatus()
        }
    }

    @MainActor
    private func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        nextReminder = await NotificationService.nextScheduledReminder()
    }
}
