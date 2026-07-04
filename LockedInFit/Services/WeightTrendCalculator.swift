import Foundation

/// Exponentially-smoothed trend weight (Hacker's Diet style) that ignores daily water noise.
enum WeightTrendCalculator {
    static let smoothing = 0.1

    struct TrendPoint: Identifiable {
        let date: Date
        let weightKg: Double
        let trendKg: Double
        var id: Date { date }
    }

    /// Entries may be unsorted; duplicates on a day are averaged.
    static func trend(entries: [BodyWeightEntry]) -> [TrendPoint] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
            .mapValues { group in group.map(\.weightKg).reduce(0, +) / Double(group.count) }
        let sortedDays = byDay.keys.sorted()
        guard let first = sortedDays.first else { return [] }

        var points: [TrendPoint] = []
        var trend = byDay[first]!
        for day in sortedDays {
            let weight = byDay[day]!
            trend += smoothing * (weight - trend)
            points.append(TrendPoint(date: day, weightKg: weight, trendKg: trend))
        }
        return points
    }

    static func currentTrendKg(entries: [BodyWeightEntry]) -> Double? {
        trend(entries: entries).last?.trendKg
    }

    /// kg/week change of the trend line over the last `days`.
    static func weeklyRate(entries: [BodyWeightEntry], days: Int = 14) -> Double? {
        let points = trend(entries: entries)
        guard let last = points.last else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: last.date)!
        guard let start = points.last(where: { $0.date <= cutoff }) ?? points.first,
              start.date < last.date else { return nil }
        let dayspan = last.date.timeIntervalSince(start.date) / 86400
        guard dayspan >= 5 else { return nil }
        return (last.trendKg - start.trendKg) / dayspan * 7
    }
}
