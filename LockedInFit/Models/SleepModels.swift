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
