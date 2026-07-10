import Foundation
import SwiftData

@Model
final class Goal {
    var phaseRaw: String = GoalPhase.maintain.rawValue
    var startDate: Date = Date()
    var startWeightKg: Double = 0
    var targetWeightKg: Double = 0
    var targetBodyFatPercentage: Double?
    var targetDate: Date?
    /// kg per week; negative for weight loss.
    var weeklyWeightChangeTarget: Double = 0
    var calorieTarget: Double = 2200
    var proteinTarget: Double = 140
    var stepTarget: Int = 8000
    /// e.g. ["waist": 80.0] target values in cm.
    var measurementGoals: [String: Double] = [:]
    var active: Bool = true

    var phase: GoalPhase {
        get { GoalPhase(rawValue: phaseRaw) ?? .maintain }
        set { phaseRaw = newValue.rawValue }
    }

    init(phase: GoalPhase,
         startDate: Date = .now,
         startWeightKg: Double = 0,
         targetWeightKg: Double,
         targetBodyFatPercentage: Double? = nil,
         targetDate: Date? = nil,
         weeklyWeightChangeTarget: Double = 0,
         calorieTarget: Double = 2200,
         proteinTarget: Double = 140,
         stepTarget: Int = 8000,
         measurementGoals: [String: Double] = [:],
         active: Bool = true) {
        self.phaseRaw = phase.rawValue
        self.startDate = startDate
        self.startWeightKg = startWeightKg
        self.targetWeightKg = targetWeightKg
        self.targetBodyFatPercentage = targetBodyFatPercentage
        self.targetDate = targetDate
        self.weeklyWeightChangeTarget = weeklyWeightChangeTarget
        self.calorieTarget = calorieTarget
        self.proteinTarget = proteinTarget
        self.stepTarget = stepTarget
        self.measurementGoals = measurementGoals
        self.active = active
    }
}

@Model
final class UserSettings {
    var heightCm: Double = 175
    var age: Int = 25
    var sexRaw: String = BiologicalSex.male.rawValue
    var unitsRaw: String = UnitSystem.metric.rawValue
    var activityAssumptionRaw: String = ActivityAssumption.light.rawValue
    /// Whether TEF is subtracted when computing effective intake.
    var applyTEF: Bool = true
    /// Manual maintenance override in kcal; nil/0 means auto-estimate.
    var manualMaintenanceOverride: Double = 0
    /// Adaptive maintenance learned from intake + weight trend, updated over time.
    var adaptiveMaintenance: Double = 0
    var adaptiveMaintenanceUpdated: Date?
    var exerciseCalorieAdjustmentRaw: String = ExerciseCalorieAdjustment.conservative.rawValue
    var sodiumLimitMg: Double = 2300
    // AI settings metadata. The API key itself lives in the Keychain only.
    /// Empty by default on purpose: AIServiceFactory.modelName treats empty
    /// as "no override", which lets AIGatewayClient resolve each provider's
    /// own free-routing model (OpenRouter's "openrouter/free" / BazaarLink's
    /// "auto:free") at call time. A non-empty stored default here would
    /// silently defeat that — every fresh install would send a fixed paid
    /// model ID forever, never actually falling through to the free
    /// default, exactly the bug this field's old "openai/gpt-4o-mini"
    /// default caused.
    var aiModelName: String = ""
    /// LEGACY, no longer consulted: providers used to be gated on this mode
    /// string, which defaulted to "mock" and silently reset on every
    /// container wipe even when a key survived in the Keychain — sending all
    /// AI analysis to fabricated mock data. Providers now key purely off
    /// whether an OpenRouter or BazaarLink key exists. Kept because
    /// persisted properties are never removed (additive-only migration
    /// policy).
    var aiModeRaw: String = "mock"
    var hasStoredAPIKey: Bool = false
    var seededSampleData: Bool = false
    var clearedEmptyWorkoutsV1: Bool = false
    // Looks & reminder settings.
    var faceReminderEnabled: Bool = false
    var faceReminderHour: Int = 9
    var faceReminderMinute: Int = 0
    var bodyReminderEnabled: Bool = false
    var bodyReminderFrequencyRaw: String = BodyReminderFrequency.off.rawValue
    var workoutRemindersEnabled: Bool = true
    /// Minutes before a scheduled session to fire local/calendar reminders.
    var defaultWorkoutReminderMinutes: Int = 60
    // Checklist-integrated notification categories. Permission is requested the
    // first time any of these is switched on (see NotificationService).
    var mealReminderEnabled: Bool = true
    var sleepReminderEnabled: Bool = true
    var sleepReminderHour: Int = 8
    var sleepReminderMinute: Int = 0
    var checklistReminderEnabled: Bool = true
    var dietaryLimitAlertsEnabled: Bool = true
    var goalAlertsEnabled: Bool = true
    /// Rolling ledger of fired one-shot event keys ("yyyy-MM-dd:kind"), so
    /// dietary-limit and goal-achievement alerts fire once per day, not on
    /// every recalculation. Pruned to the last 2 days on write.
    var notifiedEventKeys: [String] = []
    /// Whether the optional cross-app bridge to Social Climber is on: publish
    /// LockedInFit's small public snapshot, and react to Social Climber's
    /// event context. See CrossAppIntegrationManager and
    /// Settings → Social Climber.
    var crossAppSharingEnabled: Bool = true

    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }
    var units: UnitSystem {
        get { UnitSystem(rawValue: unitsRaw) ?? .metric }
        set { unitsRaw = newValue.rawValue }
    }
    var activityAssumption: ActivityAssumption {
        get { ActivityAssumption(rawValue: activityAssumptionRaw) ?? .light }
        set { activityAssumptionRaw = newValue.rawValue }
    }
    var exerciseCalorieAdjustment: ExerciseCalorieAdjustment {
        get { ExerciseCalorieAdjustment(rawValue: exerciseCalorieAdjustmentRaw) ?? .conservative }
        set { exerciseCalorieAdjustmentRaw = newValue.rawValue }
    }
    var bodyReminderFrequency: BodyReminderFrequency {
        get { BodyReminderFrequency(rawValue: bodyReminderFrequencyRaw) ?? .off }
        set { bodyReminderFrequencyRaw = newValue.rawValue }
    }

    init() {}
}
