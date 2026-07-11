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
    /// Calories from preset (known, pre-measured) foods. Excluded from the
    /// portion-underestimation uplift.
    let presetCalories: Double

    /// Midpoint of the hidden-oil range: the single value applied to calorie
    /// math everywhere (dashboard, food log, trends). Zero when no oil risk.
    var hiddenOilCalories: Double { (hiddenOilLow + hiddenOilHigh) / 2 }
    /// Logged food calories the portion uplift should scale: everything except
    /// preset foods, whose portions are known rather than eyeballed.
    var estimatedCalories: Double { max(0, calories - presetCalories) }
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
            hiddenOilHigh: dayMeals.reduce(0) { $0 + $1.hiddenOilHigh },
            presetCalories: dayMeals.reduce(0) { $0 + $1.presetCalories }
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
                        adjustment: ExerciseCalorieAdjustment,
                        bodyWeightKg: Double = 70) -> ActivityAdjustmentSummary {
        let multiplier = adjustment.multiplier

        // Steps-and-workouts estimate for the day. Apple Health's active energy
        // already folds walking and workouts together, so this is the same
        // quantity measured a cruder way — never something to add on top. Uses
        // the same weight-scaled step formula as trends and maintenance, so a
        // step burns identical calories everywhere in the app.
        let stepCount = steps.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.steps ?? 0
        let stepCalories = NutritionCalculator.stepCalories(steps: stepCount, weightKg: bodyWeightKg > 0 ? bodyWeightKg : 70)
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
    /// What you're allowed to log today: base target, plus exercise and TEF
    /// allowances, minus the hidden-oil midpoint. Oil shrinks the target
    /// rather than inflating "eaten", so eaten always matches what was
    /// actually logged.
    let adjustedTarget: Double
    /// Logged food calories only: exactly what's in the food log, no
    /// hidden-oil estimate mixed in.
    let eaten: Double
    /// Logged food calories only, before hidden oil. Identical to `eaten`;
    /// kept as a separate name for call sites that want to be explicit.
    let foodCalories: Double
    /// Hidden-oil midpoint subtracted from the target above.
    let hiddenOilCalories: Double
    /// Portion-underestimation allowance subtracted from the target: logged food
    /// scaled by the user's portion-estimation setting. Zero unless enabled.
    let portionUpliftCalories: Double
    let exerciseAdjustment: Double
    /// Thermic effect of food from what's been eaten today: calories burned
    /// digesting, added back to what's left to eat. Zero when the user has
    /// turned off "Account for TEF" in Settings.
    let tefCalories: Double
    let remaining: Double
}

/// The one source of truth for "calories remaining". Every screen that shows
/// remaining/eaten calories must go through this so dashboard, food log, and
/// summaries never disagree:
/// remaining = (target + exercise + TEF - hidden oil - portion allowance) − food.
enum CalorieRemainingCalculator {
    static func summary(baseTarget: Double,
                        nutrition: DailyNutritionSummary,
                        activityAdjustment: ActivityAdjustmentSummary,
                        tefCalories: Double = 0,
                        portionUplift: Double = 0) -> CalorieRemainingSummary {
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
        // Preset foods are pre-measured, so only the estimated (eyeballed/AI)
        // calories get the portion-underestimation uplift.
        let roundedPortion = (nutrition.estimatedCalories * portionUplift).rounded()
        let roundedFood = nutrition.calories.rounded()
        let adjustedTarget = roundedBase + roundedExercise + roundedTEF - roundedOil - roundedPortion
        return CalorieRemainingSummary(
            baseTarget: roundedBase,
            adjustedTarget: adjustedTarget,
            eaten: roundedFood,
            foodCalories: roundedFood,
            hiddenOilCalories: roundedOil,
            portionUpliftCalories: roundedPortion,
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
        // Tracked step/workout energy is credited in full; the honesty lever now
        // lives on the food side (portion estimation) instead of discounting burn.
        let adjustmentMode = ExerciseCalorieAdjustment.full
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
        let portionUplift = (settings?.portionEstimationAdjustment ?? .off).uplift
        let calories = CalorieRemainingCalculator.summary(
            baseTarget: baseTarget,
            nutrition: nutrition,
            activityAdjustment: activity,
            tefCalories: tefCalories,
            portionUplift: portionUplift
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
