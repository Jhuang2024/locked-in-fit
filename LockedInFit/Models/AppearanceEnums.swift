import Foundation

// MARK: - Appearance check-ins

enum AppearanceCheckInKind: String, Codable, CaseIterable, Identifiable {
    case face, body

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        self == .face ? "face.smiling" : "figure.stand"
    }
}

// MARK: - Suggestions

enum AppearanceSuggestionStatus: String, Codable, CaseIterable, Identifiable {
    case pending, approved, rejected, completed

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum AppearanceSuggestionCategory: String, Codable, CaseIterable, Identifiable {
    case skin, grooming, posture, workout, nutrition, sleep, body
    case photoQuality = "photo_quality"

    var id: String { rawValue }
    var label: String {
        self == .photoQuality ? "Photo Quality" : rawValue.capitalized
    }
    var systemImage: String {
        switch self {
        case .skin: return "drop.circle"
        case .grooming: return "scissors"
        case .posture: return "figure.stand"
        case .workout: return "dumbbell"
        case .nutrition: return "fork.knife"
        case .sleep: return "moon.zzz"
        case .body: return "figure.arms.open"
        case .photoQuality: return "camera.viewfinder"
        }
    }
}

enum AppearanceSuggestionDestination: String, Codable, CaseIterable, Identifiable {
    case checklist, calendar
    case workoutSchedule = "workout_schedule"
    case saveOnly = "save_only"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .checklist: return "Daily Checklist"
        case .calendar: return "Google Calendar"
        case .workoutSchedule: return "Workout Schedule"
        case .saveOnly: return "Save Only"
        }
    }
    var systemImage: String {
        switch self {
        case .checklist: return "checklist"
        case .calendar: return "calendar.badge.plus"
        case .workoutSchedule: return "calendar.day.timeline.left"
        case .saveOnly: return "tray.and.arrow.down"
        }
    }
}

enum SuggestionDurationType: String, Codable, CaseIterable, Identifiable {
    case shortTerm = "short_term"
    case longTerm = "long_term"

    var id: String { rawValue }
    var label: String { self == .shortTerm ? "Short-term" : "Long-term" }
}

// MARK: - Checklist

enum ChecklistRecurrence: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekdays, custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "One-time"
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .custom: return "Custom days"
        }
    }
}

enum ChecklistCategory: String, Codable, CaseIterable, Identifiable {
    case nutrition, workout, looks, body, face, sleep, manual

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .nutrition: return "fork.knife"
        case .workout: return "dumbbell"
        case .looks: return "sparkles"
        case .body: return "figure.arms.open"
        case .face: return "face.smiling"
        case .sleep: return "moon.zzz"
        case .manual: return "pencil"
        }
    }
}

enum ChecklistSource: String, Codable, CaseIterable {
    case manual
    case appearanceSuggestion = "appearance_suggestion"
    case workoutSchedule = "workout_schedule"
    case system

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .appearanceSuggestion: return "Appearance suggestion"
        case .workoutSchedule: return "Workout schedule"
        case .system: return "System"
        }
    }
}

// MARK: - Workout schedules

enum WorkoutScheduleGoal: String, Codable, CaseIterable, Identifiable {
    case muscleGain = "muscle_gain"
    case strength
    case fatLoss = "fat_loss"
    case maintenance
    case generalFitness = "general_fitness"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .muscleGain: return "Muscle Gain"
        case .strength: return "Strength"
        case .fatLoss: return "Fat Loss"
        case .maintenance: return "Maintenance"
        case .generalFitness: return "General Fitness"
        }
    }
}

enum WorkoutExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case beginner, intermediate, advanced

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - Reminders

enum BodyReminderFrequency: String, Codable, CaseIterable, Identifiable {
    case off, weekly
    case biweekly = "every_2_weeks"
    case monthly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Monthly"
        }
    }
    /// Days between reminders; nil when off.
    var intervalDays: Int? {
        switch self {
        case .off: return nil
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        }
    }
}

// MARK: - Weekday helper

/// Calendar-style weekday numbering shared by checklist recurrence, workout
/// schedules, and calendar sync: 1 = Sunday ... 7 = Saturday.
enum Weekday {
    static let all: [Int] = [1, 2, 3, 4, 5, 6, 7]
    static let weekdaysOnly: [Int] = [2, 3, 4, 5, 6]

    static func shortLabel(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard (1...7).contains(weekday) else { return "?" }
        return symbols[weekday - 1]
    }

    static func label(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard (1...7).contains(weekday) else { return "?" }
        return symbols[weekday - 1]
    }

    /// iCalendar RRULE day code (SU, MO, ...) for Google Calendar recurrence.
    static func rruleCode(_ weekday: Int) -> String {
        ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][max(0, min(6, weekday - 1))]
    }

    /// Next date (including `from` itself) that falls on `weekday`, at the same time of day as `from`.
    static func nextOccurrence(of weekday: Int, from: Date = .now) -> Date {
        let calendar = Calendar.current
        let current = calendar.component(.weekday, from: from)
        let delta = (weekday - current + 7) % 7
        return calendar.date(byAdding: .day, value: delta, to: from) ?? from
    }
}
