import Foundation
import UserNotifications

/// Local notification scheduling for face check-ins, body photo check-ins, and
/// workout sessions. Permission is requested only when the user enables a
/// reminder, never at launch.
enum NotificationService {

    private static let facePrefix = "face-reminder-"
    private static let bodyPrefix = "body-reminder-"
    private static let workoutPrefix = "workout-reminder-"

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
            content.body = "Optional body photo check-in — same spot, same lighting."
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
    /// user's default reminder minutes. Works fully offline — no Calendar needed.
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

    // MARK: - Helpers

    private static func removePending(prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private static var dayKeyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
}
