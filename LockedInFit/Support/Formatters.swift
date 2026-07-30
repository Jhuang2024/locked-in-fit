import Foundation

enum Formatters {
    static func kg(_ value: Double) -> String {
        String(format: "%.1f kg", value)
    }

    static func kgChange(_ value: Double) -> String {
        String(format: "%+.2f kg", value)
    }

    static func kcal(_ value: Double) -> String {
        "\(Int(value.rounded())) kcal"
    }

    static func grams(_ value: Double) -> String {
        "\(Int(value.rounded())) g"
    }

    /// Whole number when integral (100), one decimal otherwise (2.5).
    static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// How a day reads when you're navigating between days: "Today",
    /// "Yesterday", the weekday name inside the past week ("Monday"), and a
    /// dated label beyond that ("Mon, Jul 28").
    static func dayLabel(_ date: Date, relativeTo reference: Date = .now) -> String {
        let days = Calendar.current
            .dateComponents([.day], from: reference.startOfDay, to: date.startOfDay).day ?? 0
        switch days {
        case 0: return "Today"
        case -1: return "Yesterday"
        case 1: return "Tomorrow"
        case -6 ... -2: return date.formatted(.dateTime.weekday(.wide))
        default: return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }

    static func mediumDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func mediumDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// "22m" under an hour, "1h 20m" (or "1h" with no remainder) at or above.
    static func napDuration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        guard total >= 60 else { return "\(total)m" }
        let hours = total / 60, mins = total % 60
        return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: self)!
    }

    var isToday: Bool { Calendar.current.isDateInToday(self) }
}
