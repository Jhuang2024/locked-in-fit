import Foundation
import SwiftData

// MARK: - SleepLog

/// One night's sleep log. `date` is the calendar day sleep began (start of
/// day of `sleepStart`), so a log started at 11pm and ending 7am the next
/// morning is grouped under the night it started. Duration and score are
/// computed once at log time from logged data; both are deterministic, never
/// random or AI-guessed.
@Model
final class SleepLog {
    /// Stable string ID, matching the convention used by AppearanceCheckIn.
    var uuid: String = UUID().uuidString
    /// Calendar day this log belongs to: start of day of sleepStart.
    var date: Date = Date()
    var sleepStart: Date = Date()
    var sleepEnd: Date = Date()
    var wakeUps: Int = 0
    /// Hours asleep, already corrected for a midnight crossing.
    var durationHours: Double = 0
    /// 0–100 overall.
    var totalScore: Double = 0
    // Component scores out of their weights: duration/40, consistency/25,
    // interruptions/20, timing/15.
    var durationScore: Double = 0
    var consistencyScore: Double = 0
    var interruptionScore: Double = 0
    var timingScore: Double = 0
    /// "Why this score?" bullet lines, computed at log time.
    var explanations: [String] = []
    /// Actionable bullet lines for improving sleep, computed at log time.
    var suggestions: [String] = []
    /// This day's nap contribution to totalScore: positive (recovery), negative
    /// (disruptive/late), or 0. Already included in totalScore, kept separately
    /// so the detail view can show it as its own line. Recomputed whenever a
    /// nap for this day is added, edited, or removed (see SleepScoringService.recompute).
    var napContributionScore: Double = 0
    /// "How naps affected this score" bullet lines, computed alongside napContributionScore.
    var napExplanations: [String] = []
    var notes: String = ""
    var sourceRaw: String = EntrySource.manual.rawValue
    var createdAt: Date = Date()

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(date: Date,
         sleepStart: Date,
         sleepEnd: Date,
         wakeUps: Int = 0,
         durationHours: Double = 0,
         totalScore: Double = 0,
         notes: String = "",
         source: EntrySource = .manual) {
        self.date = date
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.wakeUps = wakeUps
        self.durationHours = durationHours
        self.totalScore = totalScore
        self.notes = notes
        self.sourceRaw = source.rawValue
        self.createdAt = .now
    }
}

// MARK: - NapLog

/// A single nap, stored separately from the night's SleepLog but associated
/// with the same calendar day (`date` = start of day of `napStart`). A day
/// can have any number of naps; `SleepScoringService` aggregates them into
/// that day's SleepLog whenever one is added, edited, or removed.
@Model
final class NapLog {
    var uuid: String = UUID().uuidString
    /// Calendar day this nap belongs to: start of day of napStart.
    var date: Date = Date()
    var napStart: Date = Date()
    var napEnd: Date = Date()
    /// Minutes napped, computed once at log time.
    var durationMinutes: Double = 0
    var notes: String = ""
    var sourceRaw: String = EntrySource.manual.rawValue
    var createdAt: Date = Date()

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(date: Date,
         napStart: Date,
         napEnd: Date,
         durationMinutes: Double = 0,
         notes: String = "",
         source: EntrySource = .manual) {
        self.date = date
        self.napStart = napStart
        self.napEnd = napEnd
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.sourceRaw = source.rawValue
        self.createdAt = .now
    }
}
