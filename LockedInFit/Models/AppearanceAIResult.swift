import Foundation

/// Strict JSON contract returned by the AI (or mock) appearance analyzer.
/// The AI never controls the numeric score directly: scoreAdjustment is a small
/// bounded nudge applied on top of the local AppearanceScoringService result.
struct AppearanceAIResult: Codable {
    /// -10...+10 nudge to the locally computed total score. Clamped on apply.
    var scoreAdjustment: Double
    /// 0–1 confidence in the observations.
    var confidence: Double
    /// Qualitative, non-judgmental observations about the subject and
    /// changes vs their own history — never about lighting, background, or
    /// other photo-technical qualities.
    var observations: [String]
    var suggestions: [AppearanceAISuggestion]
    /// True when the photo passed capture-time checks but the AI still
    /// couldn't reliably judge the person (e.g. subject obscured or
    /// unclear). When true, callers should ignore scoreAdjustment/suggestions
    /// and keep the local score as-is rather than penalizing the user for an
    /// unreadable photo. Optional so older/mock payloads without this field
    /// still decode.
    var unableToAssess: Bool?

    var clampedAdjustment: Double { max(-10, min(10, scoreAdjustment)) }
    var isUnableToAssess: Bool { unableToAssess ?? false }
}

struct AppearanceAISuggestion: Codable {
    var title: String
    /// Raw AppearanceSuggestionCategory value (skin/grooming/posture/workout/nutrition/sleep/body).
    /// `photo_quality` still parses for backward compatibility but the
    /// current prompt never asks the model to use it — suggestions must be
    /// about the subject, not the photo.
    var category: String
    var explanation: String
    var expectedImpact: String
    /// short_term or long_term.
    var durationType: String
    /// checklist/calendar/workout_schedule/save_only.
    var destination: String
    /// 1 = highest.
    var priority: Int

    /// Convert to a pending SwiftData suggestion; tolerant of loose enum strings.
    func makeSuggestion(sourceKind: String, checkInId: String?) -> AppearanceSuggestion {
        AppearanceSuggestion(
            sourceKind: sourceKind,
            title: title,
            explanation: explanation,
            expectedImpact: expectedImpact,
            category: AppearanceSuggestionCategory(rawValue: category)
                ?? AppearanceSuggestionCategory(rawValue: category.replacingOccurrences(of: "photoQuality", with: "photo_quality"))
                ?? .skin,
            priority: max(1, min(5, priority)),
            durationType: SuggestionDurationType(rawValue: durationType)
                ?? (durationType.lowercased().contains("long") ? .longTerm : .shortTerm),
            destination: AppearanceSuggestionDestination(rawValue: destination)
                ?? (destination.lowercased().contains("calendar") ? .calendar : .checklist),
            relatedCheckInId: checkInId)
    }
}
