import Foundation

/// Pure threshold logic for dietary-limit and goal-achievement notifications.
/// Takes today's already-computed dashboard numbers and returns the events
/// that apply right now; NotificationService.fireOnce handles dedup so each
/// event still only reaches the user once per day.
enum NotificationRulesEngine {

    /// Shared with the Dashboard's on-screen sodium warning color so the push
    /// alert and the visible indicator always agree on what "approaching"
    /// means: one threshold, not two copies that can drift apart.
    static let approachingRatio = 0.9
    static let sodiumApproachingRatio = 0.8
    static let exceededRatio = 1.0

    struct Inputs {
        let nutrition: DailyNutritionSummary
        /// Logged food calories only (same figure the Dashboard's "Eaten"
        /// stat shows, `CalorieRemainingSummary.eaten`) — the hidden-oil
        /// midpoint is subtracted from `adjustedCalorieTarget` instead, so
        /// these alerts and the on-screen numbers never disagree.
        let eaten: Double
        /// Today's base calorie target (unadjusted), same number the
        /// Dashboard's macro rings are derived from.
        let calorieTarget: Double
        /// Today's calorie target, adjusted for exercise and TEF, same
        /// number the Dashboard's "Calories Remaining" card shows.
        let adjustedCalorieTarget: Double
        let proteinTarget: Double
        let sodiumLimit: Double
        let stepsToday: Int
        let stepTarget: Int
        let completedWorkoutsToday: Int
        let now: Date
    }

    // MARK: - Dietary limits (stay-under: approaching once, exceeded once)

    static func dietaryEvents(_ input: Inputs) -> [NotificationService.NotificationEvent] {
        var events: [NotificationService.NotificationEvent] = []

        if input.adjustedCalorieTarget > 0 {
            let ratio = input.eaten / input.adjustedCalorieTarget
            if ratio >= exceededRatio {
                events.append(.init(key: "calories-exceeded", title: "Calories",
                                     body: "\(Int(input.eaten - input.adjustedCalorieTarget)) kcal over today's target."))
            } else if ratio >= approachingRatio {
                events.append(.init(key: "calories-approaching", title: "Calories",
                                     body: "\(Int(input.adjustedCalorieTarget - input.eaten)) kcal left before today's target."))
            }

            // `adjustedCalorieTarget` already bakes in the hidden-oil
            // midpoint (subtracted from the target); the remaining risk is
            // only the upside above that midpoint, not the whole range.
            let oilUpside = max(0, input.nutrition.hiddenOilHigh - input.nutrition.hiddenOilCalories)
            let projected = input.eaten + oilUpside
            if ratio < exceededRatio, oilUpside > 0, projected > input.adjustedCalorieTarget {
                events.append(.init(key: "oil-risk", title: "Hidden oil",
                                     body: "Cooking oil could push you ~\(Int(projected - input.adjustedCalorieTarget)) kcal over today."))
            }
        }

        if input.sodiumLimit > 0 {
            let ratio = input.nutrition.sodium / input.sodiumLimit
            if ratio >= exceededRatio {
                events.append(.init(key: "sodium-exceeded", title: "Sodium",
                                     body: "\(Int(input.nutrition.sodium - input.sodiumLimit)) mg over today's limit."))
            } else if ratio >= sodiumApproachingRatio {
                events.append(.init(key: "sodium-approaching", title: "Sodium",
                                     body: "\(Int(input.sodiumLimit - input.nutrition.sodium)) mg left before today's limit."))
            }
        }

        // Same derived fat guide as the Dashboard macro ring (25% of the base
        // calorie target / 9), deliberately not exercise-adjusted, to match
        // what's on screen.
        if input.calorieTarget > 0 {
            let fatTarget = max(1, (input.calorieTarget * 0.25) / 9)
            let fatRatio = input.nutrition.fat / fatTarget
            if fatRatio >= exceededRatio {
                events.append(.init(key: "fat-exceeded", title: "Fat",
                                     body: "\(Int(input.nutrition.fat - fatTarget))g over today's fat guide."))
            } else if fatRatio >= approachingRatio {
                events.append(.init(key: "fat-approaching", title: "Fat",
                                     body: "\(Int(fatTarget - input.nutrition.fat))g left before today's fat guide."))
            }
        }

        // Protein "hit" is a positive goal-achievement event, not a limit: only "approaching" lives here.
        if input.proteinTarget > 0 {
            let ratio = input.nutrition.protein / input.proteinTarget
            if ratio >= approachingRatio && ratio < exceededRatio {
                events.append(.init(key: "protein-approaching", title: "Protein",
                                     body: "\(Int(input.proteinTarget - input.nutrition.protein))g left to hit your protein target."))
            }
        }

        return events
    }

    // MARK: - Goal achievements (positive, once per day)

    static func goalEvents(_ input: Inputs, sleepGoalHit: Bool, looksChecklistComplete: Bool) -> [NotificationService.NotificationEvent] {
        var events: [NotificationService.NotificationEvent] = []

        if input.proteinTarget > 0, input.nutrition.protein >= input.proteinTarget {
            events.append(.init(key: "protein-goal-hit", title: "Protein goal",
                                 body: "Hit your protein target: \(Int(input.nutrition.protein))g."))
        }
        if input.stepTarget > 0, input.stepsToday >= input.stepTarget {
            events.append(.init(key: "step-goal-hit", title: "Steps",
                                 body: "Step goal hit: \(input.stepsToday) today."))
        }
        if input.completedWorkoutsToday > 0 {
            events.append(.init(key: "workout-completed", title: "Workout", body: "Workout logged. Nice work."))
        }
        if sleepGoalHit {
            events.append(.init(key: "sleep-goal-hit", title: "Sleep", body: "Sleep check-in done."))
        }
        if looksChecklistComplete {
            events.append(.init(key: "looks-checklist-complete", title: "Looks", body: "Face & looks checklist complete today."))
        }

        // End-of-day summary: only once it's actually evening, and only local
        // data can say so; there's no separate "end of day" concept in the app.
        if Calendar.current.component(.hour, from: input.now) >= 20,
           input.adjustedCalorieTarget > 0, input.eaten > 0 {
            let deviation = abs(input.eaten - input.adjustedCalorieTarget) / input.adjustedCalorieTarget
            if deviation <= 0.1 {
                events.append(.init(key: "calories-on-target", title: "Nutrition", body: "Calories stayed on target today."))
            }
        }

        return events
    }
}
