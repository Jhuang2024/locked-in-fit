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

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func mediumDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: self)!
    }

    var isToday: Bool { Calendar.current.isDateInToday(self) }
}
