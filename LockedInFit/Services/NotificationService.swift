import Foundation
import UserNotifications

/// Local notification scheduling for face check-ins, body photo check-ins,
/// workout sessions, meals, sleep, the daily checklist, dietary limits, and
/// goal achievements. Permission is requested only when the user enables a
/// reminder, never at launch.
///
/// @MainActor is load-bearing, not a convenience: without it these are
/// nonisolated async functions, which Swift runs on a background executor —
/// and two of them touch SwiftData models that live on the main context
/// (`refreshWorkoutReminders` walks `schedule.sessionList`, a lazily-faulted
/// relationship; `performFireOnce` reads and writes
/// `settings.notifiedEventKeys`). SwiftData models are bound to their
/// context's thread; touching them from a background thread while the main
/// thread is doing its own store work (any screen's @Query fetch) is an
/// intermittent, permanent deadlock — the app freezes forever, with the
/// stall surfacing on whatever screen happened to query next. Since every
/// call site is a view, running on the main actor costs nothing: all the
/// notification-center calls are async XPC that suspend rather than block.
@MainActor
enum NotificationService {

    private static let facePrefix = "face-reminder-"
    private static let bodyPrefix = "body-reminder-"
    private static let workoutPrefix = "workout-reminder-"
    private static let mealPrefix = "meal-reminder-"
    private static let sleepPrefix = "sleep-reminder-"
    private static let checklistDigestPrefix = "checklist-digest-"
    private static let eventPrefix = "event-"

    // MARK: - Permission

    /// Request permission if not yet determined. Returns whether notifications are allowed.
    static func ensureAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    // MARK: - Face reminder

    /// Reschedules the next 14 daily face reminders. Skips today when a face
    /// check-in already exists (or the time has passed), so there's no
    /// duplicate same-day nag. Call on launch, on settings change, and after
    /// saving a face check-in.
    static func refreshFaceReminders(enabled: Bool, hour: Int, minute: Int, faceCheckedInToday: Bool) async {
        let center = UNUserNotificationCenter.current()
        await removePending(prefix: facePrefix)
        guard enabled, await isAuthorized() else { return }

        let calendar = Calendar.current
        let dayFormatter = dayKeyFormatter
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            guard let fireDate = calendar.date(from: components) else { continue }
            if offset == 0 && (faceCheckedInToday || fireDate <= Date()) { continue }

            let content = UNMutableNotificationContent()
            content.title = "Face check-in"
            content.body = "Face check-in: take today's progress photo."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: facePrefix + dayFormatter.string(from: fireDate),
                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    // MARK: - Body reminder

    /// Schedules the next few low-frequency body photo reminders. Never daily.
    static func refreshBodyReminders(frequency: BodyReminderFrequency, hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        await removePending(prefix: bodyPrefix)
        guard let interval = frequency.intervalDays, await isAuthorized() else { return }

        let calendar = Calendar.current
        for occurrence in 1...3 {
            guard let day = calendar.date(byAdding: .day, value: interval * occurrence, to: Date()) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            let content = UNMutableNotificationContent()
            content.title = "Body check-in"
            content.body = "Optional body photo check-in: same spot, same lighting."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: bodyPrefix + "\(occurrence)",
                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    // MARK: - Workout reminders

    /// Weekly repeating reminders for a schedule's sessions, offset by the
    /// user's default reminder minutes. Works fully offline; no Calendar needed.
    static func refreshWorkoutReminders(schedule: WorkoutSchedule, enabled: Bool, offsetMinutes: Int) async {
        let center = UNUserNotificationCenter.current()
        await removePending(prefix: workoutPrefix + schedule.uuid)
        guard enabled, schedule.isActive, await isAuthorized() else { return }

        let calendar = Calendar.current
        for session in schedule.sessionList where session.reminderEnabled {
            guard let sessionDate = session.date else { continue }
            let next = Weekday.nextOccurrence(of: session.weekday, from: sessionDate)
            guard let fireDate = calendar.date(byAdding: .minute, value: -offsetMinutes, to: next) else { continue }
            var components = calendar.dateComponents([.weekday, .hour, .minute], from: fireDate)
            components.weekday = calendar.component(.weekday, from: fireDate)

            let content = UNMutableNotificationContent()
            content.title = session.title
            content.body = "\(session.title) in \(offsetMinutes) min · ~\(session.estimatedDurationMinutes) min session."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: workoutPrefix + schedule.uuid + "-\(session.weekday)",
                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func cancelWorkoutReminders(scheduleUUID: String) async {
        await removePending(prefix: workoutPrefix + scheduleUUID)
    }

    // MARK: - Meal reminders

    /// Fixed, reasonable log-time per meal. Kept simple on purpose: no
    /// per-user configuration to avoid cluttering settings.
    private static let mealTimes: [(MealType, hour: Int, minute: Int)] = [
        (.breakfast, 8, 0), (.lunch, 12, 30), (.dinner, 19, 0), (.snack, 15, 30)
    ]

    /// Schedules the next few days of meal-log reminders, skipping today's
    /// slot for any meal type already logged (so logging breakfast cancels
    /// today's breakfast nag immediately).
    static func refreshMealReminders(enabled: Bool, loggedMealTypesToday: Set<MealType>) async {
        let center = UNUserNotificationCenter.current()
        await removePending(prefix: mealPrefix)
        guard enabled, await isAuthorized() else { return }

        let calendar = Calendar.current
        let dayFormatter = dayKeyFormatter
        for (mealType, hour, minute) in mealTimes {
            for offset in 0..<3 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = hour
                components.minute = minute
                guard let fireDate = calendar.date(from: components) else { continue }
                if offset == 0 && (loggedMealTypesToday.contains(mealType) || fireDate <= Date()) { continue }

                let content = UNMutableNotificationContent()
                content.title = "Log \(mealType.label.lowercased())"
                content.body = "Quick log keeps today's calories and macros accurate."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: mealPrefix + mealType.rawValue + "-" + dayFormatter.string(from: fireDate),
                    content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }

    // MARK: - Sleep reminder

    /// A single same-day reminder to log/check off a due sleep-checklist item.
    /// Skipped once that item is completed today, or if none is due.
    static func refreshSleepReminder(enabled: Bool, hour: Int, minute: Int, dueAndIncomplete: Bool) async {
        let center = UNUserNotificationCenter.current()
        await removePending(prefix: sleepPrefix)
        guard enabled, dueAndIncomplete, await isAuthorized() else { return }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        guard let fireDate = calendar.date(from: components), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Sleep check-in"
        content.body = "Log last night's sleep on today's checklist."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: sleepPrefix + dayKeyFormatter.string(from: fireDate),
            content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Checklist digest

    /// One evening nudge for whatever's still open on Today's Checklist,
    /// beyond the categories already covered by their own reminders.
    static func refreshChecklistDigest(enabled: Bool, hour: Int, minute: Int, openCount: Int) async {
        let center = UNUserNotificationCenter.current()
        await removePending(prefix: checklistDigestPrefix)
        guard enabled, openCount > 0, await isAuthorized() else { return }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        guard let fireDate = calendar.date(from: components), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Today's checklist"
        content.body = openCount == 1 ? "1 item still open today." : "\(openCount) items still open today."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: checklistDigestPrefix + dayKeyFormatter.string(from: fireDate),
            content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Dietary limit & goal-achievement events

    /// A single fire-once notification: dietary limits ("approaching",
    /// "exceeded") and goal achievements ("hit") should each announce once
    /// per day, not on every recalculation as data changes.
    struct NotificationEvent {
        let key: String
        let title: String
        let body: String
    }

    /// Serializes `fireOnce` calls: DashboardView can trigger several of
    /// these concurrently (one per changed @Query), and without this they'd
    /// race reading/writing `settings.notifiedEventKeys`, letting the same
    /// event double-fire in one day.
    private static var fireOnceTail: Task<Void, Never> = Task {}

    /// Fires any events not already recorded for today in
    /// `settings.notifiedEventKeys`, then updates that ledger (pruned to the
    /// last 2 days so it never grows unbounded).
    static func fireOnce(_ events: [NotificationEvent], settings: UserSettings) async {
        let previous = fireOnceTail
        let current = Task {
            await previous.value
            await performFireOnce(events, settings: settings)
        }
        fireOnceTail = current
        await current.value
    }

    private static func performFireOnce(_ events: [NotificationEvent], settings: UserSettings) async {
        guard !events.isEmpty, await isAuthorized() else { return }
        let calendar = Calendar.current
        let todayKey = dayKeyFormatter.string(from: Date())
        let yesterdayKey = calendar.date(byAdding: .day, value: -1, to: Date()).map(dayKeyFormatter.string(from:))
        var fired = Set(settings.notifiedEventKeys.filter { key in
            key.hasPrefix(todayKey) || (yesterdayKey.map(key.hasPrefix) ?? false)
        })

        let center = UNUserNotificationCenter.current()
        var didFire = false
        for event in events {
            let fullKey = "\(todayKey):\(event.key)"
            guard !fired.contains(fullKey) else { continue }
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: eventPrefix + fullKey, content: content, trigger: nil)
            try? await center.add(request)
            fired.insert(fullKey)
            didFire = true
        }
        if didFire {
            settings.notifiedEventKeys = Array(fired)
        }
    }

    // MARK: - Helpers

    private static func removePending(prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Earliest upcoming scheduled reminder, for a "next reminder" status line.
    /// Ignores immediate (nil-trigger) event notifications, which aren't scheduled ahead of time.
    static func nextScheduledReminder() async -> Date? {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            .min()
    }

    private static var dayKeyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
}
