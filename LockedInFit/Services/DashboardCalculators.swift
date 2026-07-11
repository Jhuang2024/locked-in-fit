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
    /// What "consumed" means app-wide: logged calories plus hidden oil.
    var consumedCalories: Double { calories + hiddenOilCalories }
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
    /// Roughly the calories a single step burns for someone of `bodyWeightKg`.
    /// Walking energy scales with body mass, so a flat per-step number over- or
    /// under-credits people far from average weight. Anchored so a ~70 kg walker
    /// lands near the familiar 0.04 kcal/step (≈40 kcal per 1,000 steps) and a
    /// 60 kg walker near ~0.034 (≈34, inside the widely cited 32–38 range).
    static func caloriesPerStep(bodyWeightKg: Double) -> Double {
        let weight = bodyWeightKg > 0 ? bodyWeightKg : 70
        return 0.00057 * weight
    }

    static func summary(for date: Date = .now,
                        steps: [StepEntry],
                        activeEnergy: [ActiveEnergyEntry],
                        workouts: [Workout],
                        adjustment: ExerciseCalorieAdjustment,
                        bodyWeightKg: Double = 70) -> ActivityAdjustmentSummary {
        let multiplier = adjustment.multiplier

        // Steps-and-workouts estimate for the day. Apple Health's active energy
        // already folds walking and workouts together, so this is the same
        // quantity measured a cruder way — never something to add on top.
        let stepCount = steps.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.steps ?? 0
        let stepCalories = Double(stepCount) * Self.caloriesPerStep(bodyWeightKg: bodyWeightKg)
        let workoutCalories = workouts
            .filter { $0.completed && !$0.isTemplate && Calendar.current.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + Self.workoutCalories($1) }
        let estimated = stepCalories + workoutCalories

        let healthEnergy = activeEnergy
            .first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?
            .calories ?? 0

        // Prefer whichever source reports MORE burned rather than always trusting
        // Apple Health: a phone-only or not-yet-synced day can leave active energy
        // far below what the step count alone implies (e.g. ~1,000 steps reading
        // as a handful of kcal). Taking the larger of the two keeps that partial
        // reading from erasing the credit the day's steps and workouts earned,
        // while still deferring to Apple Health whenever it's the fuller number.
        if healthEnergy >= estimated && healthEnergy > 0 {
            return ActivityAdjustmentSummary(
                baseActiveCalories: healthEnergy,
                adjustmentCalories: healthEnergy * multiplier,
                multiplier: multiplier,
                sourceLabel: "Apple Health active energy",
                isEstimated: false
            )
        }

        return ActivityAdjustmentSummary(
            baseActiveCalories: estimated,
            adjustmentCalories: estimated * multiplier,
            multiplier: multiplier,
            sourceLabel: "steps and workouts",
            isEstimated: estimated > 0
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
    let adjustedTarget: Double
    /// Consumed calories counted against the target: logged food plus the
    /// hidden-oil midpoint.
    let eaten: Double
    /// Logged food calories only, before hidden oil.
    let foodCalories: Double
    /// Hidden-oil midpoint applied on top of logged food.
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
/// summaries never disagree: remaining = (target + exercise + TEF) − (food + hidden oil).
enum CalorieRemainingCalculator {
    static func summary(baseTarget: Double,
                        nutrition: DailyNutritionSummary,
                        activityAdjustment: ActivityAdjustmentSummary,
                        tefCalories: Double = 0) -> CalorieRemainingSummary {
        let adjustedTarget = baseTarget + activityAdjustment.adjustmentCalories + tefCalories
        return CalorieRemainingSummary(
            baseTarget: baseTarget,
            adjustedTarget: adjustedTarget,
            eaten: nutrition.consumedCalories,
            foodCalories: nutrition.calories,
            hiddenOilCalories: nutrition.hiddenOilCalories,
            exerciseAdjustment: activityAdjustment.adjustmentCalories,
            tefCalories: tefCalories,
            remaining: adjustedTarget - nutrition.consumedCalories
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
        let bodyWeightKg = WeightTrendCalculator.currentTrendKg(entries: weights) ?? weights.last?.weightKg ?? 70
        let activity = ActivityAdjustmentCalculator.summary(
            for: date,
            steps: steps,
            activeEnergy: activeEnergy,
            workouts: workouts,
            adjustment: adjustmentMode,
            bodyWeightKg: bodyWeightKg
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
            todayCalories: nutrition.consumedCalories,
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
