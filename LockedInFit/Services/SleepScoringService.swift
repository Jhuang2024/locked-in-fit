import Foundation

/// Local, deterministic sleep scoring: duration, consistency vs. the user's
/// own recent bedtime history, interruptions, bedtime timing, and same-day
/// naps. Every point is traceable to logged data, never random or AI-guessed.
/// This is the only place sleep score math happens; the sleep page, score
/// detail page, and trends all read the persisted result instead of
/// recomputing it themselves.
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
        /// Same-day nap contribution, already folded into `total`. Capped to
        /// napBonusCap...napPenaltyCap so naps can help or hurt but never
        /// dominate the overnight components.
        var napContribution: Double
        /// "Why this score?" bullet lines (overnight components only).
        var explanations: [String]
        /// Actionable bullet lines for improving sleep.
        var suggestions: [String]
        /// "How naps affected this score" bullet lines.
        var napExplanations: [String]
    }

    private static let idealDurationRange = 7.0...9.0
    private static let idealBedtimeRange = 21.0...23.5

    // Nap scoring tuning. Kept small relative to the 100-point overnight
    // total so overnight sleep always remains the dominant driver.
    private static let idealNapRange = 10.0...30.0
    /// Below this, overnight sleep counts as "very low"; long or late naps
    /// are treated as legitimate recovery instead of disruptive.
    private static let lowOvernightThreshold = 5.0
    private static let napEarlyCutoffHour = 15.0 // 3pm: naps before this are unpenalized for timing.
    private static let napLateCutoffHour = 18.0  // 6pm: naps at/after this are penalized unless overnight sleep was very low.
    static let napBonusCap = 7.0
    static let napPenaltyCap = -10.0

    /// Sleep duration in hours, correcting for sleep that crosses midnight:
    /// a wake time at or before bedtime implies the wake time is the next day.
    static func durationHours(sleepStart: Date, sleepEnd: Date) -> Double {
        var interval = sleepEnd.timeIntervalSince(sleepStart)
        if interval <= 0 { interval += 86400 }
        return interval / 3600
    }

    /// - Parameters:
    ///   - naps: this same calendar day's naps (see NapLog.date).
    ///   - date: the night this log belongs to (defaults to now); used only
    ///     to decide which prior logs count as "history" for consistency.
    ///   - now: wall-clock time of scoring, used only to decide whether it's
    ///     still early enough in the day to suggest a recovery nap.
    static func score(sleepStart: Date, sleepEnd: Date, wakeUps: Int,
                      history: [SleepLog], naps: [NapLog] = [],
                      date: Date = .now, now: Date = .now) -> SleepScoreResult {
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

        // Nap recovery/disruption: capped and scaled by overnight deficit so
        // naps can nudge the score but never replace a good night's sleep.
        let nap = napContribution(overnightHours: hours, naps: naps)
        if hours < idealDurationRange.lowerBound, naps.isEmpty,
           Calendar.current.component(.hour, from: now) < 15 {
            suggestions.append("Consider a short 10-20 minute nap earlier today to help recover some of last night's sleep debt.")
        }

        let total = min(100, max(0, duration + consistency + interruptions + timing + nap.points))
        return SleepScoreResult(total: total, duration: duration, consistency: consistency,
                                interruptions: interruptions, timing: timing, napContribution: nap.points,
                                explanations: explanations, suggestions: suggestions, napExplanations: nap.explanations)
    }

    /// Writes a computed result onto a SleepLog, the one place score fields
    /// get assigned so creation and recomputation never drift apart.
    static func apply(_ result: SleepScoreResult, to log: SleepLog) {
        log.totalScore = result.total
        log.durationScore = result.duration
        log.consistencyScore = result.consistency
        log.interruptionScore = result.interruptions
        log.timingScore = result.timing
        log.napContributionScore = result.napContribution
        log.explanations = result.explanations
        log.suggestions = result.suggestions
        log.napExplanations = result.napExplanations
    }

    /// Recomputes and persists `log`'s score from its own overnight data plus
    /// the current `naps` for that day. Call this after any nap for `log`'s
    /// day is added, edited, or removed, so the log's score always reflects
    /// same-day naps without a second scoring implementation.
    static func recompute(_ log: SleepLog, history: [SleepLog], naps: [NapLog]) {
        let result = score(sleepStart: log.sleepStart, sleepEnd: log.sleepEnd, wakeUps: log.wakeUps,
                           history: history, naps: naps, date: log.sleepStart)
        apply(result, to: log)
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

    // MARK: - Nap scoring

    private struct NapEvaluation {
        let nap: NapLog
        /// Points after duration, timing, and deficit scaling; before
        /// cross-nap weighting and the final cap.
        let points: Double
        let isLate: Bool
        let veryLate: Bool
    }

    /// Combines a day's naps into one capped contribution: the best nap
    /// counts fully, each additional nap counts for progressively less (so
    /// stacking naps can't keep raising the score), and 3+ naps add a small
    /// flat penalty for fragmented sleep. Overnight sleep remaining strong
    /// caps how much even a well-timed nap can add.
    private static func napContribution(overnightHours: Double, naps: [NapLog]) -> (points: Double, explanations: [String]) {
        guard !naps.isEmpty else { return (0, []) }

        let scale = deficitScale(overnightHours: overnightHours)
        let evaluations = naps
            .map { evaluateNap($0, overnightHours: overnightHours, deficitScale: scale) }
            .sorted { $0.points > $1.points }

        let weights: [Double] = [1.0, 0.4, 0.2]
        var weightedSum = 0.0
        for (index, evaluation) in evaluations.enumerated() {
            let weight = index < weights.count ? weights[index] : 0.1
            weightedSum += evaluation.points * weight
        }
        if naps.count >= 3 {
            weightedSum -= Double(naps.count - 2)
        }
        let finalPoints = max(napPenaltyCap, min(napBonusCap, weightedSum))

        var lines: [String] = []
        let totalMinutes = naps.reduce(0.0) { $0 + $1.durationMinutes }
        lines.append(naps.count == 1
            ? "You logged 1 nap today totaling \(Formatters.napDuration(totalMinutes))."
            : "You logged \(naps.count) naps today totaling \(Formatters.napDuration(totalMinutes)).")

        if let best = evaluations.first {
            let timeLabel = best.nap.napStart.formatted(date: .omitted, time: .shortened)
            let minutesLabel = Int(best.nap.durationMinutes.rounded())
            if best.points > 0.5 {
                lines.append("Your \(minutesLabel) minute nap at \(timeLabel) helped recover some sleep debt.")
            } else if best.points < -0.5 {
                lines.append(best.veryLate
                    ? "Your \(minutesLabel) minute nap at \(timeLabel) was late in the day, so it may interfere with tonight's sleep."
                    : "Your \(minutesLabel) minute nap ran long, which can leave you groggier and may disrupt tonight's sleep structure.")
            } else {
                lines.append("Your \(minutesLabel) minute nap at \(timeLabel) had little effect either way on today's score.")
            }
        }

        if scale < 0.5, weightedSum > 0 {
            lines.append("Nap benefit was capped because overnight sleep is still the main driver of recovery.")
        }
        if naps.count >= 3 {
            lines.append("Multiple naps today can signal fragmented sleep, so extra naps count for less.")
        }
        if finalPoints == 0 {
            lines.append("Naps had no net effect on today's score.")
        } else if finalPoints > 0 {
            lines.append("Naps added +\(Int(finalPoints.rounded())) points to today's score.")
        } else {
            lines.append("Naps subtracted \(Int(finalPoints.rounded())) points from today's score.")
        }

        return (finalPoints, lines)
    }

    private static func evaluateNap(_ nap: NapLog, overnightHours: Double, deficitScale: Double) -> NapEvaluation {
        let veryLow = overnightHours < lowOvernightThreshold
        let base = napDurationPoints(minutes: nap.durationMinutes, veryLowOvernight: veryLow)
        let (adjusted, isLate, veryLate) = napTimingAdjustment(basePoints: base, napStart: nap.napStart, veryLowOvernight: veryLow)
        let scaled = adjusted > 0 ? adjusted * deficitScale : adjusted
        return NapEvaluation(nap: nap, points: scaled, isLate: isLate, veryLate: veryLate)
    }

    /// How much of a positive nap contribution overnight deficit unlocks:
    /// 0.2 (little/no bonus) when overnight sleep already meets the 7h
    /// floor, scaling up to 1.0 (full bonus) once the deficit reaches 3h.
    /// Never scales penalties: a disruptive nap is disruptive regardless of
    /// how little sleep came before it.
    private static func deficitScale(overnightHours: Double) -> Double {
        let deficit = max(0, idealDurationRange.lowerBound - overnightHours)
        let capped = min(deficit, 3.0)
        return 0.2 + (capped / 3.0) * 0.8
    }

    /// -10...+8 from duration alone, before timing/deficit adjustments.
    /// Peaks at 10-30 min, tapers through 60 min, turns negative beyond that,
    /// and drops sharply past 90 min unless overnight sleep was very low
    /// (then a long nap reads as legitimate recovery, not disruption).
    private static func napDurationPoints(minutes: Double, veryLowOvernight: Bool) -> Double {
        if minutes < 5 { return 0 }
        if minutes < idealNapRange.lowerBound {
            return (minutes - 5) / (idealNapRange.lowerBound - 5) * 6
        }
        if idealNapRange.contains(minutes) { return 8 }
        if minutes <= 60 {
            let t = (minutes - idealNapRange.upperBound) / (60 - idealNapRange.upperBound)
            return 8 - t * 7
        }
        if minutes <= 90 {
            let t = (minutes - 60) / 30
            return 1 - t * 7
        }
        return veryLowOvernight ? -2 : -10
    }

    /// Dampens/amplifies a nap's duration points by how late it started.
    /// Before 3pm: unchanged. 3-6pm: positive halved, negative worsened
    /// slightly. 6pm+: heavily dampened/worsened, unless overnight sleep was
    /// very low, in which case it's treated as recovery sleep instead.
    private static func napTimingAdjustment(basePoints: Double, napStart: Date, veryLowOvernight: Bool) -> (points: Double, isLate: Bool, veryLate: Bool) {
        let hour = napStartHour(napStart)
        if hour < napEarlyCutoffHour { return (basePoints, false, false) }
        if hour < napLateCutoffHour {
            let adjusted = basePoints > 0 ? basePoints * 0.5 : basePoints * 1.2
            return (adjusted, true, false)
        }
        if veryLowOvernight {
            return (basePoints * 0.7, true, true)
        }
        let adjusted = (basePoints > 0 ? basePoints * 0.15 : basePoints * 1.4) - 2
        return (adjusted, true, true)
    }

    /// Hour-of-day (0-24, with minutes as a fraction) a nap started.
    private static func napStartHour(_ date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
    }
}
