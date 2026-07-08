import Foundation

struct GoalProjection {
    var currentTrendKg: Double?
    var weeklyRateKg: Double?
    var projectedFinishDate: Date?
    var paceWarning: String?
    /// 0–100: how close actual weekly rate is to the target.
    var adherenceScore: Int
    var recommendedCalories: Double
    var recommendedProtein: Double
    var recommendedSteps: Int
}

enum GoalProjectionCalculator {

    static func project(goal: Goal, weightEntries: [BodyWeightEntry]) -> GoalProjection {
        let trendKg = WeightTrendCalculator.currentTrendKg(entries: weightEntries)
        let rate = WeightTrendCalculator.weeklyRate(entries: weightEntries)

        var finish: Date?
        if let trendKg, let rate, abs(rate) > 0.02 {
            let remaining = goal.targetWeightKg - trendKg
            // Only projects if moving toward the target.
            if remaining * rate > 0 {
                let weeks = remaining / rate
                if weeks < 260 {
                    finish = Calendar.current.date(byAdding: .day, value: Int(weeks * 7), to: .now)
                }
            }
        }

        var warning: String?
        if let trendKg {
            let remaining = goal.targetWeightKg - trendKg
            if let targetDate = goal.targetDate {
                let weeksLeft = max(0.1, targetDate.timeIntervalSinceNow / (86400 * 7))
                let requiredRate = remaining / weeksLeft
                if abs(requiredRate) > 1.0 {
                    warning = "Hitting \(Formatters.kg(goal.targetWeightKg)) by \(Formatters.shortDate(targetDate)) needs \(Formatters.kgChange(requiredRate))/week. That pace is unrealistic and would cost muscle. Extend the date or adjust the target."
                } else if abs(requiredRate) > 0.75, goal.phase == .cut {
                    warning = "Required pace of \(Formatters.kgChange(requiredRate))/week is aggressive. Expect hunger and plan protein carefully."
                }
            }
            if goal.phase == .cut, let rate, rate > 0.1 {
                warning = warning ?? "Trend weight is moving up while cutting. Check intake logging and hidden oil."
            }
            if (goal.phase == .leanBulk || goal.phase == .aggressiveBulk), let rate, rate < -0.1 {
                warning = warning ?? "Trend weight is dropping during a bulk. Eat more."
            }
        }

        // Adherence: how close observed rate is to target rate (100 = on pace).
        var adherence = 50
        if let rate {
            let target = goal.weeklyWeightChangeTarget
            if abs(target) < 0.05 {
                adherence = max(0, 100 - Int(abs(rate) * 200)) // maintain: penalize drift
            } else {
                let ratio = rate / target // 1.0 = perfect, negative = wrong direction
                if ratio <= 0 {
                    adherence = 10
                } else {
                    adherence = max(0, min(100, Int(100 - abs(ratio - 1) * 80)))
                }
            }
        }

        // These are the actual targets saved from the Goal form (Settings →
        // Goal), never recomputed here: recalculating them from the current
        // maintenance estimate silently showed different numbers than what
        // was entered and saved. NutritionCalculator's formulas already ran
        // once, in GoalEditView's "Auto-fill from maintenance estimate", and
        // their result is what got saved onto the goal.
        return GoalProjection(
            currentTrendKg: trendKg,
            weeklyRateKg: rate,
            projectedFinishDate: finish,
            paceWarning: warning,
            adherenceScore: adherence,
            recommendedCalories: goal.calorieTarget,
            recommendedProtein: goal.proteinTarget,
            recommendedSteps: goal.stepTarget
        )
    }
}
