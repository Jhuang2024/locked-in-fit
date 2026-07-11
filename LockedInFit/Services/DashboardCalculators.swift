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

    /// Midpoint of the hidden-oil range: the single value applied to calorie
    /// math everywhere (dashboard, food log, trends). Zero when no oil risk.
    var hiddenOilCalories: Double { (hiddenOilLow + hiddenOilHigh) / 2 }
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
            .reduce(0) { $0 + Self.workoutCalories($1) }
        let total = stepCalories + workoutCalories

        return ActivityAdjustmentSummary(
            baseActiveCalories: total,
            adjustmentCalories: total * multiplier,
            multiplier: multiplier,
            sourceLabel: "Estimated from steps and workouts",
            isEstimated: total > 0
        )
    }

    /// The calories a specific logged workout burned: its own stored value
    /// (manually entered, or from an AI description estimate) when set,
    /// otherwise the duration/type/RPE heuristic as a default.
    static func workoutCalories(_ workout: Workout) -> Double {
        workout.caloriesBurned > 0 ? workout.caloriesBurned : estimatedWorkoutCalories(workout)
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
    /// What you're allowed to log today: base target, plus exercise and TEF
    /// allowances, minus the hidden-oil midpoint. Oil shrinks the target
    /// rather than inflating "eaten", so eaten always matches what was
    /// actually logged.
    let adjustedTarget: Double
    /// Logged food calories only — exactly what's in the food log, no
    /// hidden-oil estimate mixed in.
    let eaten: Double
    /// Logged food calories only, before hidden oil. Identical to `eaten`;
    /// kept as a separate name for call sites that want to be explicit.
    let foodCalories: Double
    /// Hidden-oil midpoint subtracted from the target above.
    let hiddenOilCalories: Double
    let exerciseAdjustment: Double
    /// Thermic effect of food from what's been eaten today: calories burned
    /// digesting, added back to what's left to eat. Zero when the user has
    /// turned off "Account for TEF" in Settings.
    let tefCalories: Double
    let remaining: Double
}

/// The one source of truth for "calories remaining". Every screen that shows
/// remaining/eaten calories must go through this so dashboard, food log, and
/// summaries never disagree: remaining = (target + exercise + TEF - hidden oil) − food.
enum CalorieRemainingCalculator {
    static func summary(baseTarget: Double,
                        nutrition: DailyNutritionSummary,
                        activityAdjustment: ActivityAdjustmentSummary,
                        tefCalories: Double = 0) -> CalorieRemainingSummary {
        // Round each atomic kcal figure once, here, rather than carrying
        // Doubles through and letting every display site round its own chip
        // independently. Doing it per-chip means "Target" (rounded from the
        // precise, un-rounded sum) can differ from what a user gets by
        // adding up the Base/Exercise/TEF chips (each independently
        // rounded) right next to it — e.g. 1899.6 + 0.6 + 26.4 rounds to
        // chips reading 1900 / +1 / +26 (= 1927 by hand) while the precise
        // sum 1926.6 itself rounds to 1927... but shift those fractions
        // slightly and the two paths land on different whole numbers.
        // Calories are a whole-number concept for display anyway, so
        // rounding once at the source guarantees every screen's numbers
        // always add up exactly, by construction.
        let roundedBase = baseTarget.rounded()
        let roundedExercise = activityAdjustment.adjustmentCalories.rounded()
        let roundedTEF = tefCalories.rounded()
        let roundedOil = nutrition.hiddenOilCalories.rounded()
        let roundedFood = nutrition.calories.rounded()
        let adjustedTarget = roundedBase + roundedExercise + roundedTEF - roundedOil
        return CalorieRemainingSummary(
            baseTarget: roundedBase,
            adjustedTarget: adjustedTarget,
            eaten: roundedFood,
            foodCalories: roundedFood,
            hiddenOilCalories: roundedOil,
            exerciseAdjustment: roundedExercise,
            tefCalories: roundedTEF,
            remaining: adjustedTarget - roundedFood
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
        let tefCalories = (settings?.applyTEF ?? true)
            ? NutritionCalculator.tef(protein: nutrition.protein, carbs: nutrition.carbs, fat: nutrition.fat)
            : 0
        let calories = CalorieRemainingCalculator.summary(
            baseTarget: baseTarget,
            nutrition: nutrition,
            activityAdjustment: activity,
            tefCalories: tefCalories
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
            todayCalories: calories.eaten,
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
