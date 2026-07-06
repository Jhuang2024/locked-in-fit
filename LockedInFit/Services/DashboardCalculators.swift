import Foundation

struct DailyNutritionSummary {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sodium: Double
    let hiddenOilLow: Double
    let hiddenOilHigh: Double
}

enum DailyNutritionCalculator {
    static func summary(for date: Date = .now, meals: [MealLog]) -> DailyNutritionSummary {
        let dayMeals = meals.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        return DailyNutritionSummary(
            calories: dayMeals.reduce(0) { $0 + $1.calories },
            protein: dayMeals.reduce(0) { $0 + $1.protein },
            carbs: dayMeals.reduce(0) { $0 + $1.carbs },
            fat: dayMeals.reduce(0) { $0 + $1.fat },
            fiber: dayMeals.reduce(0) { $0 + $1.fiber },
            sodium: dayMeals.reduce(0) { $0 + $1.sodium },
            hiddenOilLow: dayMeals.reduce(0) { $0 + $1.hiddenOilLow },
            hiddenOilHigh: dayMeals.reduce(0) { $0 + $1.hiddenOilHigh }
        )
    }
}

struct ActivityAdjustmentSummary {
    let baseActiveCalories: Double
    let adjustmentCalories: Double
    let multiplier: Double
    let sourceLabel: String
    let isEstimated: Bool
}

enum ActivityAdjustmentCalculator {
    static func summary(for date: Date = .now,
                        steps: [StepEntry],
                        activeEnergy: [ActiveEnergyEntry],
                        workouts: [Workout],
                        adjustment: ExerciseCalorieAdjustment) -> ActivityAdjustmentSummary {
        let multiplier = adjustment.multiplier
        if let healthEnergy = activeEnergy.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }),
           healthEnergy.calories > 0 {
            return ActivityAdjustmentSummary(
                baseActiveCalories: healthEnergy.calories,
                adjustmentCalories: healthEnergy.calories * multiplier,
                multiplier: multiplier,
                sourceLabel: "Apple Health active energy",
                isEstimated: false
            )
        }

        let stepCount = steps.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.steps ?? 0
        let stepCalories = Double(stepCount) * 0.04
        let workoutCalories = workouts
            .filter { $0.completed && !$0.isTemplate && Calendar.current.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + estimatedWorkoutCalories($1) }
        let total = stepCalories + workoutCalories

        return ActivityAdjustmentSummary(
            baseActiveCalories: total,
            adjustmentCalories: total * multiplier,
            multiplier: multiplier,
            sourceLabel: "Estimated from steps and workouts",
            isEstimated: total > 0
        )
    }

    static func estimatedWorkoutCalories(_ workout: Workout) -> Double {
        guard workout.completed, workout.duration > 0 else { return 0 }
        let minutes = workout.duration
        let rpe = workout.perceivedDifficulty > 0 ? Double(workout.perceivedDifficulty) : 6
        let intensityScale = min(1.2, max(0.8, rpe / 7.0))
        let kcalPerMinute: Double

        switch workout.type {
        case .strength, .upperLower, .pushPullLegs, .fullBody:
            kcalPerMinute = 5
        case .hypertrophy:
            kcalPerMinute = 6
        case .conditioning:
            kcalPerMinute = 10
        case .mobility:
            kcalPerMinute = 2.5
        case .custom:
            kcalPerMinute = 5
        }

        return minutes * kcalPerMinute * intensityScale
    }
}

struct CalorieRemainingSummary {
    let baseTarget: Double
    let adjustedTarget: Double
    let eaten: Double
    let exerciseAdjustment: Double
    let remaining: Double
}

enum CalorieRemainingCalculator {
    static func summary(baseTarget: Double,
                        caloriesEaten: Double,
                        activityAdjustment: ActivityAdjustmentSummary) -> CalorieRemainingSummary {
        let adjustedTarget = baseTarget + activityAdjustment.adjustmentCalories
        return CalorieRemainingSummary(
            baseTarget: baseTarget,
            adjustedTarget: adjustedTarget,
            eaten: caloriesEaten,
            exerciseAdjustment: activityAdjustment.adjustmentCalories,
            remaining: adjustedTarget - caloriesEaten
        )
    }
}

struct DashboardViewModel {
    let nutrition: DailyNutritionSummary
    let activity: ActivityAdjustmentSummary
    let calories: CalorieRemainingSummary
    let proteinTarget: Double
    let stepTarget: Int
    let stepsToday: Int
    let completedWorkoutsToday: Int
    let weeklyCalorieAverage: Double?
    let lockedInScore: Int

    init(settings: UserSettings?,
         goal: Goal?,
         meals: [MealLog],
         weights: [BodyWeightEntry],
         steps: [StepEntry],
         activeEnergy: [ActiveEnergyEntry],
         workouts: [Workout],
         date: Date = .now) {
        let maintenance = settings.map {
            Analytics.estimateMaintenance(settings: $0, weights: weights, meals: meals, steps: steps)
        } ?? 2400
        let baseTarget = goal?.calorieTarget ?? maintenance
        let proteinTarget = goal?.proteinTarget ?? 140
        let stepTarget = goal?.stepTarget ?? 8000
        let adjustmentMode = settings?.exerciseCalorieAdjustment ?? .conservative
        let nutrition = DailyNutritionCalculator.summary(for: date, meals: meals)
        let activity = ActivityAdjustmentCalculator.summary(
            for: date,
            steps: steps,
            activeEnergy: activeEnergy,
            workouts: workouts,
            adjustment: adjustmentMode
        )
        let calories = CalorieRemainingCalculator.summary(
            baseTarget: baseTarget,
            caloriesEaten: nutrition.calories,
            activityAdjustment: activity
        )
        let todaySteps = steps.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.steps ?? 0
        let todayWorkouts = workouts.filter {
            $0.completed && !$0.isTemplate && Calendar.current.isDate($0.date, inSameDayAs: date)
        }.count
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? date.daysAgo(7)
        let workoutsThisWeek = workouts.filter { $0.completed && !$0.isTemplate && $0.date >= weekStart }.count

        self.nutrition = nutrition
        self.activity = activity
        self.calories = calories
        self.proteinTarget = proteinTarget
        self.stepTarget = stepTarget
        self.stepsToday = todaySteps
        self.completedWorkoutsToday = todayWorkouts
        self.weeklyCalorieAverage = Self.weeklyCalorieAverage(meals: meals, date: date)
        self.lockedInScore = Analytics.lockedInScore(
            todayCalories: nutrition.calories,
            calorieTarget: calories.adjustedTarget,
            todayProtein: nutrition.protein,
            proteinTarget: proteinTarget,
            todaySteps: todaySteps,
            stepTarget: stepTarget,
            trainedThisWeek: workoutsThisWeek,
            weeklyTrainingTarget: 4
        )
    }

    private static func weeklyCalorieAverage(meals: [MealLog], date: Date) -> Double? {
        let cutoff = date.daysAgo(7).startOfDay
        let grouped = Analytics.dailyCalories(meals.filter { $0.date >= cutoff })
        guard !grouped.isEmpty else { return nil }
        return grouped.values.reduce(0, +) / Double(grouped.count)
    }
}
