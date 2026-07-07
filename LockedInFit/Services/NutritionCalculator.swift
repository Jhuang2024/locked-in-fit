import Foundation

/// TEF, BMR, and adaptive maintenance estimation.
enum NutritionCalculator {

    /// Thermic effect of food from macro grams.
    /// protein 20–30%, carbs 5–10%, fat 0–3%; midpoints used.
    static func tef(protein: Double, carbs: Double, fat: Double) -> Double {
        let proteinKcal = protein * 4 * 0.25
        let carbKcal = carbs * 4 * 0.075
        let fatKcal = fat * 9 * 0.015
        return proteinKcal + carbKcal + fatKcal
    }

    /// Mifflin-St Jeor BMR.
    static func bmr(weightKg: Double, heightCm: Double, age: Int, sex: BiologicalSex) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    /// Calories burned by steps, roughly 0.04 kcal per step per (weight/70kg).
    static func stepCalories(steps: Int, weightKg: Double) -> Double {
        Double(steps) * 0.04 * (weightKg / 70)
    }

    /// Formula-based maintenance estimate.
    static func formulaMaintenance(weightKg: Double, heightCm: Double, age: Int, sex: BiologicalSex,
                                   avgDailySteps: Int, activity: ActivityAssumption) -> Double {
        let base = bmr(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex)
        return base * activity.nonStepMultiplier + stepCalories(steps: avgDailySteps, weightKg: weightKg)
    }

    /// Adaptive maintenance from observed intake and trend-weight change:
    /// maintenance ≈ avg intake − (Δ trend weight kg × 7700) / days.
    /// Returns nil when there isn't enough data to trust it.
    static func observedMaintenance(dailyIntakes: [Double], trendWeightStartKg: Double,
                                    trendWeightEndKg: Double, days: Int) -> Double? {
        guard days >= 10, dailyIntakes.count >= 7 else { return nil }
        let avgIntake = dailyIntakes.reduce(0, +) / Double(dailyIntakes.count)
        guard avgIntake > 800 else { return nil } // sparse logging, don't trust
        let deltaKg = trendWeightEndKg - trendWeightStartKg
        return avgIntake - (deltaKg * 7700) / Double(days)
    }

    /// Blend formula and observed maintenance; observed gains weight as data accumulates.
    static func blendedMaintenance(formula: Double, observed: Double?, observationDays: Int) -> Double {
        guard let observed, observed > 1000, observed < 6000 else { return formula }
        let observedWeight = min(0.75, Double(observationDays) / 28.0 * 0.75)
        return formula * (1 - observedWeight) + observed * observedWeight
    }

    /// Calorie target for a weekly weight-change goal on top of maintenance.
    static func calorieTarget(maintenance: Double, weeklyChangeKg: Double) -> Double {
        maintenance + (weeklyChangeKg * 7700) / 7
    }

    /// Protein target by phase (g/kg bodyweight).
    static func proteinTarget(weightKg: Double, phase: GoalPhase) -> Double {
        let perKg: Double
        switch phase {
        case .cut: perKg = 2.2
        case .maintain: perKg = 1.8
        case .leanBulk: perKg = 1.8
        case .aggressiveBulk: perKg = 1.6
        case .custom: perKg = 2.0
        }
        return (weightKg * perKg).rounded()
    }
}
