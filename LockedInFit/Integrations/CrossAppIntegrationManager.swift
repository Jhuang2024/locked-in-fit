import Foundation

/// Optional, fail-safe bridge between LockedInFit and Social Climber. Reads
/// and writes only small, versioned JSON snapshots through
/// `SharedContextStore`, never the other app's private database, and never
/// LockedInFit's own SwiftData store. Every read degrades to "no context"
/// (missing App Group, missing file, stale data, corrupt JSON, unrecognized
/// schema); LockedInFit must behave identically whether or not Social
/// Climber is installed or up to date.
///
/// This file is the only place that knows about Social Climber. Everything
/// downstream (checklist generation, the dashboard card) consumes plain
/// values from here, not the raw shared-context types.
enum CrossAppIntegrationManager {
    /// Context older than this is treated as unavailable rather than risking
    /// a stale "event tonight" suggestion on the wrong day.
    static let staleAfter: TimeInterval = 24 * 3600

    // MARK: - Publish

    struct PublishInput {
        var sleepScore: Double?
        var workoutPlannedToday: Bool
        var workoutCompletedToday: Bool
        var nutritionEatenCalories: Double
        var nutritionTargetCalories: Double
        var hasLoggedFoodToday: Bool
        /// Fraction (0...1) of today's due checklist items already completed.
        var dailyChecklistCompletion: Double
        var importantTasks: [ImportantTaskInput]
        var isSick: Bool
    }

    struct ImportantTaskInput {
        var id: String
        var title: String
        var category: LockedInFitPublicContext.HealthTaskCategory
        var overdue: Bool
    }

    /// Builds and writes today's public snapshot. Safe to call often (it
    /// rides along with the existing reminder-refresh cycle); a missing App
    /// Group container simply makes this a no-op.
    @discardableResult
    static func publish(_ input: PublishInput, now: Date = .now) -> Bool {
        let snapshot = LockedInFitPublicContext(
            updatedAt: now,
            today: .init(
                sleepScore: input.sleepScore ?? 0,
                // Sick overrides the sleep-derived read: a well-rested but
                // sick day is still a low-energy, poor-recovery one, and this
                // way older Social Climber builds that don't know `isSick`
                // yet still get a sane signal from the fields they do read.
                energyLevel: input.isSick ? .low : energyLevel(forSleepScore: input.sleepScore),
                recoveryStatus: input.isSick ? .poor : recoveryStatus(forSleepScore: input.sleepScore),
                workoutPlannedToday: input.workoutPlannedToday,
                workoutCompletedToday: input.workoutCompletedToday,
                nutritionStatus: nutritionStatus(input),
                calorieStatus: calorieStatus(input),
                dailyChecklistCompletion: input.dailyChecklistCompletion,
                importantHealthTasksDue: input.importantTasks.prefix(5).map {
                    LockedInFitPublicContext.HealthTask(
                        id: $0.id, title: $0.title, category: $0.category,
                        priority: $0.overdue ? .high : .medium)
                },
                isSick: input.isSick))
        return SharedContextStore.writeLockedInFitContext(snapshot)
    }

    private static func energyLevel(forSleepScore score: Double?) -> LockedInFitPublicContext.EnergyLevel {
        guard let score else { return .unknown }
        if score >= 80 { return .high }
        if score >= 55 { return .medium }
        return .low
    }

    private static func recoveryStatus(forSleepScore score: Double?) -> LockedInFitPublicContext.RecoveryStatus {
        guard let score else { return .unknown }
        if score >= 75 { return .good }
        if score >= 50 { return .okay }
        return .poor
    }

    private static func nutritionStatus(_ input: PublishInput) -> LockedInFitPublicContext.NutritionStatus {
        guard input.hasLoggedFoodToday, input.nutritionTargetCalories > 0 else { return .unknown }
        let ratio = input.nutritionEatenCalories / input.nutritionTargetCalories
        if ratio >= NotificationRulesEngine.exceededRatio { return .overLimit }
        if ratio >= NotificationRulesEngine.approachingRatio { return .approachingLimit }
        if ratio < 0.5 { return .underTarget }
        return .onTrack
    }

    private static func calorieStatus(_ input: PublishInput) -> LockedInFitPublicContext.CalorieStatus {
        guard input.hasLoggedFoodToday, input.nutritionTargetCalories > 0 else { return .unknown }
        let ratio = input.nutritionEatenCalories / input.nutritionTargetCalories
        if ratio >= NotificationRulesEngine.exceededRatio { return .exceeded }
        if ratio >= NotificationRulesEngine.approachingRatio { return .nearLimit }
        return .remaining
    }

    // MARK: - Read

    /// Today's Social Climber context, or nil if unavailable, stale (older
    /// than 24h), or corrupt. Accepts any schema version at or above the one
    /// LockedInFit understands, since the defensive decoding in
    /// `SocialClimberPublicContext` already tolerates additive changes.
    static func readSocialContext(now: Date = .now) -> SocialClimberPublicContext.Today? {
        guard let context = SharedContextStore.readSocialClimberContext(),
              context.schemaVersion >= SocialClimberPublicContext.expectedSchemaVersion else { return nil }
        let age = now.timeIntervalSince(context.updatedAt)
        guard age >= 0, age <= staleAfter else { return nil }
        return context.today
    }

    // MARK: - Social readiness

    /// A same-day-relevant Social Climber event worth reacting to, reduced to
    /// exactly what the dashboard/checklist need: never the raw event list.
    struct SocialReadiness {
        var eventToday: Bool
        var eventTomorrow: Bool
        var summaryText: String
    }

    /// Whether today's Social Climber context contains an event worth
    /// surfacing today or tomorrow: high importance, or flagged as needing
    /// prep. Low-stakes events (importance low/medium with no prep) stay
    /// silent so this doesn't nag on ordinary days.
    static func socialReadiness(from today: SocialClimberPublicContext.Today?) -> SocialReadiness? {
        guard let today else { return nil }
        let notable = today.upcomingEvents.filter { $0.importance == .high || $0.prepNeeded }
        let eventToday = notable.contains { Calendar.current.isDateInToday($0.startTime) }
        let eventTomorrow = notable.contains { Calendar.current.isDateInTomorrow($0.startTime) }
        guard eventToday || eventTomorrow else { return nil }
        let summaryText = eventToday
            ? "Social event tonight. Keep energy stable: hydrate, avoid skipping meals, and finish key checklist items early."
            : "Social event tomorrow. Prioritize sleep tonight so you show up rested."
        return SocialReadiness(eventToday: eventToday, eventTomorrow: eventTomorrow, summaryText: summaryText)
    }
}
