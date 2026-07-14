import Foundation

/// The "brief feed" LockedInFit publishes for Brief (the morning-briefing
/// app) to read from the shared App Group container: a per-day summary of
/// recent activity plus upcoming reminders. Unlike the peer-bridge snapshot
/// (`LockedInFitPublicContext`, deliberately minimal because another app
/// consumes it), this feed is written for the user's own eyes in their own
/// morning brief, so it carries real detail: workout titles, calories,
/// sleep scores, checklist item titles.
///
/// The contract lives in the Brief repo's LINKED_APPS.md. Brief decodes
/// defensively, but changes here must stay additive (new optional fields
/// only) so older Brief builds keep reading newer feeds. Encode-only:
/// LockedInFit writes this file and never reads it back.
struct LockedInFitBriefFeed: Encodable {
    static let currentSchemaVersion = 1

    var app: String = "LockedInFit"
    var schemaVersion: Int = currentSchemaVersion
    /// When the feed was written (ISO-8601 via SharedContextStore's encoder).
    var generatedAt: Date
    /// Up to 3 most recent local days with any data, newest first.
    var days: [Day]
    /// Overdue plus due-within-2-days entries, at most 12, overdue first
    /// then by due date.
    var reminders: [Reminder]

    struct Day: Encodable {
        /// Local calendar day, "yyyy-MM-dd" (see BriefFeedPublisher.dayKeyFormatter).
        var date: String
        /// At most 8 human-readable summary lines, most important first.
        var lines: [String]
    }

    struct Reminder: Encodable {
        /// Stable across writes: the source model's uuid, suffixed with the
        /// occurrence day for recurring items so today's and tomorrow's
        /// projections of the same item never collide.
        var id: String
        var title: String
        /// Optional secondary text; synthesized Encodable omits the key when nil.
        var detail: String?
        var dueDate: Date
        /// True → Brief hides the time (the entry has no specific time of day).
        var isAllDay: Bool
        /// Past due and incomplete at write time.
        var overdue: Bool
    }
}
