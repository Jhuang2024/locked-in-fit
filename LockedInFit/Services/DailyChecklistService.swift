import Foundation
import SwiftData

/// Due/complete logic for the Today checklist. Recurring items are single
/// persistent records; "completed today" is derived from completedAt so they
/// reset automatically each day.
enum DailyChecklistService {

    /// Is this item due on the given day?
    static func isDue(_ item: DailyChecklistItem, on date: Date = .now) -> Bool {
        let calendar = Calendar.current
        let day = date.startOfDay
        guard item.createdAt.startOfDay <= day else { return false }
        switch item.recurrence {
        case .none:
            if item.isCompleted {
                // Completed one-time items only show on their completion day.
                return item.completedAt.map { calendar.isDate($0, inSameDayAs: date) } ?? false
            }
            // Due on its due date, and kept visible while overdue.
            return item.dueDate.startOfDay <= day
        case .daily:
            return true
        case .weekdays:
            return Weekday.weekdaysOnly.contains(calendar.component(.weekday, from: date))
        case .custom:
            return item.customWeekdays.contains(calendar.component(.weekday, from: date))
        }
    }

    /// Completed for the given day (recurring items reset daily).
    static func isCompleted(_ item: DailyChecklistItem, on date: Date = .now) -> Bool {
        switch item.recurrence {
        case .none:
            return item.isCompleted
        default:
            return item.completedAt.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
        }
    }

    static func toggle(_ item: DailyChecklistItem, on date: Date = .now) {
        if isCompleted(item, on: date) {
            item.completedAt = nil
            item.isCompleted = false
        } else {
            item.completedAt = date
            item.isCompleted = true
        }
    }

    static func dueItems(_ items: [DailyChecklistItem], on date: Date = .now) -> [DailyChecklistItem] {
        items.filter { isDue($0, on: date) }
            .sorted { a, b in
                let aDone = isCompleted(a, on: date), bDone = isCompleted(b, on: date)
                if aDone != bDone { return !aDone } // incomplete first
                return a.createdAt < b.createdAt
            }
    }

    /// Due-and-incomplete items outside `.sleep`, which has its own reminder
    /// category — shared by the Dashboard's reminder refresh and the
    /// Notifications settings screen so both agree on what the checklist
    /// digest covers.
    static func openItemsExcludingSleep(_ items: [DailyChecklistItem], on date: Date = .now) -> [DailyChecklistItem] {
        dueItems(items, on: date).filter { $0.category != .sleep && !isCompleted($0, on: date) }
    }

    /// Whether a due `.sleep` item is still open today.
    static func sleepItemDueIncomplete(_ items: [DailyChecklistItem], on date: Date = .now) -> Bool {
        dueItems(items, on: date).contains { $0.category == .sleep && !isCompleted($0, on: date) }
    }

    /// Create (and insert) a checklist item from an approved suggestion.
    @discardableResult
    static func createItem(from suggestion: AppearanceSuggestion,
                           recurrence: ChecklistRecurrence,
                           customWeekdays: [Int],
                           context: ModelContext) -> DailyChecklistItem {
        let category: ChecklistCategory
        switch suggestion.category {
        case .skin, .grooming, .photoQuality: category = .looks
        case .posture, .body: category = .body
        case .workout: category = .workout
        case .nutrition: category = .nutrition
        case .sleep: category = .sleep
        }
        let item = DailyChecklistItem(
            title: suggestion.title,
            details: suggestion.explanation,
            category: category,
            dueDate: .now,
            recurrence: recurrence,
            customWeekdays: customWeekdays,
            source: .appearanceSuggestion,
            sourceId: suggestion.uuid)
        context.insert(item)
        suggestion.checklistItemId = item.uuid
        suggestion.recurrenceRule = recurrence.rawValue
        return item
    }
}
