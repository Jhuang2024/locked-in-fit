import Foundation
import SwiftData

// MARK: - AppearanceCheckIn

/// One face or body check-in. Scores are explainable component values, not a
/// claim about objective attractiveness: they reflect photo quality, composition
/// data, grooming/consistency proxies, and self-comparison against the user's
/// own history. Raw photos stay on-device via ImageStore.
@Model
final class AppearanceCheckIn {
    /// Stable string ID so suggestions can reference a check-in across saves.
    var uuid: String = UUID().uuidString
    var date: Date = Date()
    var kindRaw: String = AppearanceCheckInKind.face.rawValue
    /// Face photo (kind == .face).
    var photoPath: String?
    /// Body photos (kind == .body).
    var frontPhotoPath: String?
    var sidePhotoPath: String?
    var backPhotoPath: String?
    /// 0–100 overall.
    var totalScore: Double = 0
    // Component scores. Face uses quality/skin/symmetry/grooming/puffiness/trend;
    // body uses composition/muscularity/posture/trend/quality. Unused ones stay 0.
    var qualityScore: Double = 0
    var compositionScore: Double = 0
    var skinScore: Double = 0
    var symmetryScore: Double = 0
    var groomingScore: Double = 0
    var puffinessScore: Double = 0
    var muscularityScore: Double = 0
    var postureScore: Double = 0
    var trendScore: Double = 0
    /// 0–1. Drops with poor photo quality or missing composition data.
    var confidence: Double = 0
    var notes: String = ""
    /// Face width/height ratio from Vision landmarks; used only for
    /// self-comparison puffiness tracking across the user's own history. 0 = unknown.
    var faceWidthHeightRatio: Double = 0
    var createdAt: Date = Date()

    var kind: AppearanceCheckInKind {
        get { AppearanceCheckInKind(rawValue: kindRaw) ?? .face }
        set { kindRaw = newValue.rawValue }
    }

    var allPhotoPaths: [String?] { [photoPath, frontPhotoPath, sidePhotoPath, backPhotoPath] }

    init(date: Date = .now,
         kind: AppearanceCheckInKind,
         photoPath: String? = nil,
         frontPhotoPath: String? = nil,
         sidePhotoPath: String? = nil,
         backPhotoPath: String? = nil,
         totalScore: Double = 0,
         confidence: Double = 0,
         notes: String = "") {
        self.date = date
        self.kindRaw = kind.rawValue
        self.photoPath = photoPath
        self.frontPhotoPath = frontPhotoPath
        self.sidePhotoPath = sidePhotoPath
        self.backPhotoPath = backPhotoPath
        self.totalScore = totalScore
        self.confidence = confidence
        self.notes = notes
        self.createdAt = .now
    }
}

// MARK: - AppearanceSuggestion

@Model
final class AppearanceSuggestion {
    /// Stable string ID so checklist items can reference their source suggestion.
    var uuid: String = UUID().uuidString
    var createdAt: Date = Date()
    /// face/body/workout/manual — where the suggestion came from.
    var sourceKindRaw: String = "face"
    var title: String = ""
    var explanation: String = ""
    var expectedImpact: String = ""
    var categoryRaw: String = AppearanceSuggestionCategory.skin.rawValue
    /// 1 = highest priority.
    var priority: Int = 3
    var statusRaw: String = AppearanceSuggestionStatus.pending.rawValue
    var destinationRaw: String = AppearanceSuggestionDestination.saveOnly.rawValue
    var durationTypeRaw: String = SuggestionDurationType.shortTerm.rawValue
    /// Recurrence for checklist items created from this suggestion.
    var recurrenceRule: String?
    var suggestedDate: Date?
    var calendarEventId: String?
    var checklistItemId: String?
    /// UUID of the AppearanceCheckIn that produced this suggestion.
    var relatedCheckInId: String?

    var category: AppearanceSuggestionCategory {
        get { AppearanceSuggestionCategory(rawValue: categoryRaw) ?? .skin }
        set { categoryRaw = newValue.rawValue }
    }
    var status: AppearanceSuggestionStatus {
        get { AppearanceSuggestionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
    var destination: AppearanceSuggestionDestination {
        get { AppearanceSuggestionDestination(rawValue: destinationRaw) ?? .saveOnly }
        set { destinationRaw = newValue.rawValue }
    }
    var durationType: SuggestionDurationType {
        get { SuggestionDurationType(rawValue: durationTypeRaw) ?? .shortTerm }
        set { durationTypeRaw = newValue.rawValue }
    }

    init(sourceKind: String,
         title: String,
         explanation: String,
         expectedImpact: String,
         category: AppearanceSuggestionCategory,
         priority: Int = 3,
         durationType: SuggestionDurationType = .shortTerm,
         destination: AppearanceSuggestionDestination = .saveOnly,
         relatedCheckInId: String? = nil) {
        self.createdAt = .now
        self.sourceKindRaw = sourceKind
        self.title = title
        self.explanation = explanation
        self.expectedImpact = expectedImpact
        self.categoryRaw = category.rawValue
        self.priority = priority
        self.durationTypeRaw = durationType.rawValue
        self.destinationRaw = destination.rawValue
        self.relatedCheckInId = relatedCheckInId
    }
}

// MARK: - DailyChecklistItem

@Model
final class DailyChecklistItem {
    /// Stable string ID so suggestions/schedules can link back to this item.
    var uuid: String = UUID().uuidString
    var title: String = ""
    var details: String = ""
    var categoryRaw: String = ChecklistCategory.manual.rawValue
    var createdAt: Date = Date()
    var dueDate: Date = Date()
    var completedAt: Date?
    var isCompleted: Bool = false
    var recurrenceRaw: String = ChecklistRecurrence.none.rawValue
    /// Calendar weekdays (1 = Sunday ... 7 = Saturday) for .custom recurrence.
    var customWeekdays: [Int] = []
    var sourceRaw: String = ChecklistSource.manual.rawValue
    /// UUID of the source object (suggestion, schedule session).
    var sourceId: String?
    var calendarEventId: String?

    var category: ChecklistCategory {
        get { ChecklistCategory(rawValue: categoryRaw) ?? .manual }
        set { categoryRaw = newValue.rawValue }
    }
    var recurrence: ChecklistRecurrence {
        get { ChecklistRecurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }
    var source: ChecklistSource {
        get { ChecklistSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(title: String,
         details: String = "",
         category: ChecklistCategory = .manual,
         dueDate: Date = .now,
         recurrence: ChecklistRecurrence = .none,
         customWeekdays: [Int] = [],
         source: ChecklistSource = .manual,
         sourceId: String? = nil) {
        self.title = title
        self.details = details
        self.categoryRaw = category.rawValue
        self.createdAt = .now
        self.dueDate = dueDate
        self.recurrenceRaw = recurrence.rawValue
        self.customWeekdays = customWeekdays
        self.sourceRaw = source.rawValue
        self.sourceId = sourceId
    }
}

// MARK: - CalendarConnectionState

/// Connection metadata only. OAuth tokens live in the Keychain, never here.
@Model
final class CalendarConnectionState {
    var isConnected: Bool = false
    var email: String = ""
    var grantedScopes: [String] = []
    var lastSyncDate: Date?

    init(isConnected: Bool = false, email: String = "", grantedScopes: [String] = []) {
        self.isConnected = isConnected
        self.email = email
        self.grantedScopes = grantedScopes
    }
}
