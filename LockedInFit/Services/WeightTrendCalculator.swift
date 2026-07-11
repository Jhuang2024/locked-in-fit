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

        // Time-aware EWMA. `smoothing` is calibrated for daily weigh-ins, so
        // translate it into a decay time constant and weight each update by the
        // ACTUAL gap between readings rather than treating every entry as one
        // step. Without this, sparse or irregular logging (or a stale imported
        // weight) drags the trend far longer than it should: a weigh-in a week
        // later would smooth as gently as one the next day, leaving the "current"
        // trend and weekly rate anchored to old values. With it, a long gap
        // mostly resets the trend to the fresh reading, so "current" figures
        // track recent weight instead of lagging months behind.
        let tau = -1.0 / log(1 - smoothing)   // days; ≈9.5 for smoothing 0.1
        var points: [TrendPoint] = []
        var trend = byDay[first]!
        var previousDay = first
        for day in sortedDays {
            let weight = byDay[day]!
            let gapDays = day.timeIntervalSince(previousDay) / 86400
            let alpha = 1 - exp(-gapDays / tau)   // 0 on the seed day, →1 after long gaps
            trend += alpha * (weight - trend)
            points.append(TrendPoint(date: day, weightKg: weight, trendKg: trend))
            previousDay = day
        }
        return points
    }

    /// Default lookback for "current" figures so a long-ago HealthKit import
    /// (e.g. a heavier weight from years back) doesn't anchor the EWMA and
    /// take dozens of readings to converge back to the present.
    static let defaultRecentWindowDays = 120

    /// Entries from the last `days`, falling back to the full history if that
    /// window has no data (e.g. a fresh import with no recent weigh-ins yet).
    static func recent(_ entries: [BodyWeightEntry], days: Int = defaultRecentWindowDays) -> [BodyWeightEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let windowed = entries.filter { $0.date >= cutoff }
        return windowed.isEmpty ? entries : windowed
    }

    static func currentTrendKg(entries: [BodyWeightEntry]) -> Double? {
        trend(entries: recent(entries)).last?.trendKg
    }

    /// The most recently logged scale reading (not smoothed). This is what the
    /// dashboard shows as the user's current weight.
    static func latestKg(entries: [BodyWeightEntry]) -> Double? {
        entries.max(by: { $0.date < $1.date })?.weightKg
    }

    /// kg/week change measured between the two most recent logged entries.
    /// Returns nil when there is no earlier entry to compare against, or when
    /// both entries share the same day (no measurable weekly span).
    static func weeklyChangeFromEntries(entries: [BodyWeightEntry]) -> Double? {
        let sorted = entries.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return nil }
        let latest = sorted[sorted.count - 1]
        let previous = sorted[sorted.count - 2]
        let daysBetween = latest.date.timeIntervalSince(previous.date) / 86400
        let weeksBetween = daysBetween / 7.0
        guard weeksBetween > 0 else { return nil }
        return (latest.weightKg - previous.weightKg) / weeksBetween
    }

    /// kg/week change of the trend line over the last `days`.
    static func weeklyRate(entries: [BodyWeightEntry], days: Int = 14) -> Double? {
        let points = trend(entries: recent(entries))
        guard let last = points.last else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: last.date)!
        guard let start = points.last(where: { $0.date <= cutoff }) ?? points.first,
              start.date < last.date else { return nil }
        let dayspan = last.date.timeIntervalSince(start.date) / 86400
        guard dayspan >= 5 else { return nil }
        return (last.trendKg - start.trendKg) / dayspan * 7
    }
}
