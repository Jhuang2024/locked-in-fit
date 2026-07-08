import Foundation
import SwiftData

/// Turns a fresh, non-stale Social Climber context into ordinary LockedInFit
/// checklist items, reusing DailyChecklistItem/DailyChecklistService
/// end-to-end instead of a second task system. Every generated item is owned
/// by LockedInFit (ChecklistSource.socialClimberEvent) and keyed by day so
/// re-running this on the same day never duplicates a suggestion.
enum EventAwareChecklistService {

    /// Inserts any missing event-aware tasks for today and returns how many
    /// were added. Safe to call on every dashboard refresh.
    @discardableResult
    static func generateItems(readiness: CrossAppIntegrationManager.SocialReadiness,
                              workoutPlannedToday: Bool,
                              existing: [DailyChecklistItem],
                              context: ModelContext,
                              today: Date = .now) -> Int {
        var candidates: [(key: String, title: String, category: ChecklistCategory)] = []

        if readiness.eventToday {
            candidates.append(("hydrate", "Hydrate before tonight's event", .nutrition))
            candidates.append(("light-meal", "Avoid a heavy or bloating meal before tonight's event", .nutrition))
            candidates.append(("grooming", "Complete your grooming/self-care checklist before tonight's event", .looks))
            if workoutPlannedToday {
                candidates.append(("earlier-workout", "Move today's workout earlier because of tonight's plans", .workout))
            }
        }
        if readiness.eventTomorrow {
            candidates.append(("sleep-priority", "Prioritize sleep tonight for tomorrow's event", .sleep))
        }

        let dayKey = dayKey(today)
        let existingSourceIds = Set(existing.compactMap(\.sourceId))
        var inserted = 0
        for candidate in candidates {
            let sourceId = "social-\(candidate.key)-\(dayKey)"
            guard !existingSourceIds.contains(sourceId) else { continue }
            let item = DailyChecklistItem(
                title: candidate.title,
                details: "Suggested from an upcoming event on your calendar.",
                category: candidate.category,
                dueDate: today,
                recurrence: .none,
                source: .socialClimberEvent,
                sourceId: sourceId)
            context.insert(item)
            inserted += 1
        }
        return inserted
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
