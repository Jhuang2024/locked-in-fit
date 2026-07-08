import Foundation

/// Shared aggregation helpers used by dashboard, trends, and goal screens.
enum Analytics {

    /// Consumed calories per day from meal logs: logged calories plus the
    /// hidden-oil midpoint, matching the dashboard/food-log "eaten" number so
    /// trends and maintenance estimation use the same intake figure.
    static func dailyCalories(_ meals: [MealLog]) -> [Date: Double] {
        Dictionary(grouping: meals) { $0.date.startOfDay }
            .mapValues { $0.reduce(0) { $0 + $1.consumedCalories } }
    }

    static func dailyProtein(_ meals: [MealLog]) -> [Date: Double] {
        Dictionary(grouping: meals) { $0.date.startOfDay }
            .mapValues { $0.reduce(0) { $0 + $1.protein } }
    }

    /// TEF (thermic effect of food) per day, from that day's total macros:
    /// the same figure the dashboard adds back into the day's calorie target.
    static func dailyTEF(_ meals: [MealLog]) -> [Date: Double] {
        Dictionary(grouping: meals) { $0.date.startOfDay }
            .mapValues { dayMeals in
                NutritionCalculator.tef(
                    protein: dayMeals.reduce(0) { $0 + $1.protein },
                    carbs: dayMeals.reduce(0) { $0 + $1.carbs },
                    fat: dayMeals.reduce(0) { $0 + $1.fat })
            }
    }

    static func avgDailySteps(_ steps: [StepEntry], days: Int = 14) -> Int {
        let cutoff = Date().daysAgo(days).startOfDay
        let recent = steps.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return 7000 }
        return recent.reduce(0) { $0 + $1.steps } / recent.count
    }

    /// Best current maintenance estimate: formula blended with observed intake-vs-trend data.
    static func estimateMaintenance(settings: UserSettings,
                                    weights: [BodyWeightEntry],
                                    meals: [MealLog],
                                    steps: [StepEntry]) -> Double {
        if settings.manualMaintenanceOverride > 500 {
            return settings.manualMaintenanceOverride
        }
        let currentWeight = WeightTrendCalculator.currentTrendKg(entries: weights) ?? weights.last?.weightKg ?? 75
        let formula = NutritionCalculator.formulaMaintenance(
            weightKg: currentWeight,
            heightCm: settings.heightCm,
            age: settings.age,
            sex: settings.sex,
            avgDailySteps: avgDailySteps(steps),
            activity: settings.activityAssumption)

        // Observed window: last 21 days of intake + trend change.
        let windowDays = 21
        let cutoff = Date().daysAgo(windowDays).startOfDay
        let calorieByDay = dailyCalories(meals.filter { $0.date >= cutoff })
        let intakes = Array(calorieByDay.values)
        let trendPoints = WeightTrendCalculator.trend(entries: weights)
        let startTrend = trendPoints.last(where: { $0.date <= cutoff })?.trendKg ?? trendPoints.first?.trendKg
        let endTrend = trendPoints.last?.trendKg

        var observed: Double?
        if let startTrend, let endTrend {
            observed = NutritionCalculator.observedMaintenance(
                dailyIntakes: intakes,
                trendWeightStartKg: startTrend,
                trendWeightEndKg: endTrend,
                days: windowDays)
        }
        return NutritionCalculator.blendedMaintenance(formula: formula, observed: observed, observationDays: intakes.count).rounded()
    }

    /// "Locked In" daily score 0–100, entirely earned from today's logged behavior.
    /// A day with nothing logged yet must read as 0; no free credit.
    static func lockedInScore(todayCalories: Double, calorieTarget: Double,
                              todayProtein: Double, proteinTarget: Double,
                              todaySteps: Int, stepTarget: Int,
                              trainedThisWeek: Int, weeklyTrainingTarget: Int) -> Int {
        var score = 0.0
        // Nutrition (34): within ±10% of target is full credit, fades to 0 at ±40%.
        if calorieTarget > 0, todayCalories > 0 {
            let deviation = abs(todayCalories - calorieTarget) / calorieTarget
            score += 34 * max(0, min(1, (0.4 - deviation) / 0.3))
        }
        // Protein (28)
        if proteinTarget > 0 {
            score += 28 * min(1, todayProtein / proteinTarget)
        }
        // Steps (22)
        if stepTarget > 0 {
            score += 22 * min(1, Double(todaySteps) / Double(stepTarget))
        }
        // Training (16): sessions this week vs target frequency.
        if weeklyTrainingTarget > 0 {
            score += 16 * min(1, Double(trainedThisWeek) / Double(weeklyTrainingTarget))
        }
        return Int(score.rounded())
    }
}
