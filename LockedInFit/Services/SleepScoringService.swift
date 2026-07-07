import Foundation

/// Local, deterministic sleep scoring: duration, consistency vs. the user's
/// own recent bedtime history, interruptions, and bedtime timing. Every point
/// is traceable to logged data, never random or AI-guessed.
enum SleepScoringService {

    struct SleepScoreResult {
        /// 0–100.
        var total: Double
        /// Component points out of their weights: duration/40, consistency/25,
        /// interruptions/20, timing/15.
        var duration: Double
        var consistency: Double
        var interruptions: Double
        var timing: Double
        /// "Why this score?" bullet lines.
        var explanations: [String]
        /// Actionable bullet lines for improving sleep.
        var suggestions: [String]
    }

    private static let idealDurationRange = 7.0...9.0
    private static let idealBedtimeRange = 21.0...23.5

    /// Sleep duration in hours, correcting for sleep that crosses midnight:
    /// a wake time at or before bedtime implies the wake time is the next day.
    static func durationHours(sleepStart: Date, sleepEnd: Date) -> Double {
        var interval = sleepEnd.timeIntervalSince(sleepStart)
        if interval <= 0 { interval += 86400 }
        return interval / 3600
    }

    /// - Parameter date: the night this log belongs to (defaults to now); used
    ///   only to decide which prior logs count as "history" for consistency.
    static func score(sleepStart: Date, sleepEnd: Date, wakeUps: Int,
                      history: [SleepLog], date: Date = .now) -> SleepScoreResult {
        var explanations: [String] = []
        var suggestions: [String] = []

        let hours = durationHours(sleepStart: sleepStart, sleepEnd: sleepEnd)

        // Duration (40): peaks across 7-9h, tapers steeply below (fatigue), gently above.
        let duration = durationPoints(hours: hours)
        if idealDurationRange.contains(hours) {
            explanations.append("\(Formatters.trimmed(hours))h of sleep is in the ideal 7-9h range.")
        } else if hours < idealDurationRange.lowerBound {
            explanations.append("\(Formatters.trimmed(hours))h is short of the 7-9h range most adults need.")
            suggestions.append("Move bedtime earlier by about \(Int((idealDurationRange.lowerBound - hours) * 60)) minutes to reach 7 hours.")
        } else {
            explanations.append("\(Formatters.trimmed(hours))h is above the 7-9h range; oversleeping can leave you groggier than a full, on-time night.")
            suggestions.append("Try waking within 30-60 minutes of the same time even on rest days.")
        }

        // Consistency (25): tonight's bedtime vs. the median bedtime of the
        // last up-to-7 prior nights. Needs 3+ prior nights to be meaningful.
        let startMinutes = minutesSinceMidnight(sleepStart)
        let priorMinutes = history
            .filter { $0.date < date.startOfDay }
            .sorted { $0.date < $1.date }
            .suffix(7)
            .map { minutesSinceMidnight($0.sleepStart) }
        let (consistency, hasHistory) = consistencyPoints(startMinutes: startMinutes, history: priorMinutes)
        if !hasHistory {
            explanations.append("Bedtime consistency needs a few more nights logged to compare against your baseline.")
        } else if consistency >= 20 {
            explanations.append("Bedtime is close to your recent average; consistent sleep timing is doing real work here.")
        } else {
            explanations.append("Bedtime has drifted from your recent average, which makes sleep less restorative even at the same duration.")
            suggestions.append("Pick one target bedtime and hold it within 30 minutes, even on weekends.")
        }

        // Interruptions (20): each wake-up during the night costs points.
        let interruptions = interruptionPoints(wakeUps: wakeUps)
        if wakeUps == 0 {
            explanations.append("No wake-ups logged; uninterrupted sleep is one of the biggest levers for how rested you feel.")
        } else {
            explanations.append("\(wakeUps) wake-up\(wakeUps == 1 ? "" : "s") logged overnight; each one fragments deep sleep.")
            suggestions.append(wakeUps >= 3
                ? "Frequent wake-ups; check room temperature, screens before bed, caffeine timing, and evening fluid intake."
                : "Cut caffeine after midday and keep the room cool and dark to reduce wake-ups.")
        }

        // Timing (15): how close bedtime is to a circadian-friendly window.
        let timing = timingPoints(sleepStart: sleepStart)
        if timing >= 12 {
            explanations.append("Bedtime falls in a circadian-friendly window (9:00-11:30pm).")
        } else {
            explanations.append("Bedtime is outside the 9:00-11:30pm window that lines up best with natural melatonin release.")
            suggestions.append("Dim lights and put screens away 30 minutes before your target bedtime.")
        }

        let total = min(100, duration + consistency + interruptions + timing)
        return SleepScoreResult(total: total, duration: duration, consistency: consistency,
                                interruptions: interruptions, timing: timing,
                                explanations: explanations, suggestions: suggestions)
    }

    /// Consecutive nights ending today/yesterday with at least one sleep log.
    static func streak(history: [SleepLog], endingAt date: Date = .now) -> Int {
        let days = Set(history.map { $0.date.startOfDay })
        guard !days.isEmpty else { return 0 }
        var cursor = date.startOfDay
        if !days.contains(cursor) {
            cursor = cursor.daysAgo(1)
            guard days.contains(cursor) else { return 0 }
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = cursor.daysAgo(1)
        }
        return streak
    }

    // MARK: - Component formulas

    /// 0-40. Peaks across 7-9h, tapers steeply below (fatigue), gently above.
    private static func durationPoints(hours: Double) -> Double {
        if idealDurationRange.contains(hours) { return 40 }
        if hours < idealDurationRange.lowerBound {
            let under = idealDurationRange.lowerBound - hours
            return max(0, 40 - under * 13)
        }
        let over = hours - idealDurationRange.upperBound
        return max(20, 40 - over * 8)
    }

    /// 0-25. Circular distance between tonight's bedtime and the median of up
    /// to the last 7 nights' bedtimes. Returns (points, hadEnoughHistory).
    private static func consistencyPoints(startMinutes: Double, history: [Double]) -> (Double, Bool) {
        guard history.count >= 3 else { return (18, false) }
        let baseline = AppearanceScoringService.median(history)
        let rawDelta = abs(startMinutes - baseline)
        let delta = min(rawDelta, 1440 - rawDelta)
        return (max(0, min(25, 25 - delta / 12)), true)
    }

    /// 0-20. Each wake-up costs 5 points.
    private static func interruptionPoints(wakeUps: Int) -> Double {
        max(0, 20 - Double(wakeUps) * 5)
    }

    /// 0-15. Peaks 9:00pm-11:30pm; later bedtimes cost more than earlier ones.
    private static func timingPoints(sleepStart: Date) -> Double {
        var hour = Double(Calendar.current.component(.hour, from: sleepStart))
            + Double(Calendar.current.component(.minute, from: sleepStart)) / 60
        if hour < 5 { hour += 24 } // past-midnight bedtime reads as "very late"
        if idealBedtimeRange.contains(hour) { return 15 }
        if hour < idealBedtimeRange.lowerBound {
            return max(8, 15 - (idealBedtimeRange.lowerBound - hour) * 3)
        }
        return max(0, 15 - (hour - idealBedtimeRange.upperBound) * 6)
    }

    /// Minutes since midnight, 0-1440, for circular bedtime comparison.
    private static func minutesSinceMidnight(_ date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }
}
