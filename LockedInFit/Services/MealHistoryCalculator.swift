import Foundation

/// One day of food history: the meals logged that day plus the same nutrition
/// and calorie math the dashboard runs for "today", evaluated for that day.
struct DayFoodSummary: Identifiable {
    /// Start of the calendar day this summarizes.
    let date: Date
    /// That day's meals, earliest first.
    let meals: [MealLog]
    let nutrition: DailyNutritionSummary
    let calories: CalorieRemainingSummary

    var id: Date { date }
    var isEmpty: Bool { meals.isEmpty }
    /// Negative when the day went over its adjusted target.
    var remaining: Double { calories.remaining }
}

/// Day-by-day food history, built from the same shared calculators the Today
/// dashboard and the Food Log's own totals use, so "yesterday" here reads
/// exactly as it did on the dashboard while it was still today.
///
/// The one deliberate difference: the sick-day calorie allowance only applies
/// to the current day, since `UserSettings.isSickToday` describes today and
/// nothing else. Maintenance and body weight are, as on the dashboard,
/// current estimates rather than per-day historical ones; they're computed
/// once here instead of per day, which is both faster and exactly what
/// DashboardViewModel would produce for each of those days.
enum MealHistoryCalculator {

    /// Newest day first, one entry per calendar day between the window start
    /// and the most recent day with anything logged (or today, whichever is
    /// later). Days with nothing logged are included so a gap reads as
    /// "nothing logged" instead of silently vanishing from the list.
    ///
    /// - Parameter days: window length in days, counting today; nil for every
    ///   day back to the first meal ever logged.
    static func summaries(meals: [MealLog],
                          goal: Goal?,
                          settings: UserSettings?,
                          weights: [BodyWeightEntry] = [],
                          steps: [StepEntry] = [],
                          activeEnergy: [ActiveEnergyEntry] = [],
                          workouts: [Workout] = [],
                          days: Int? = nil,
                          today: Date = .now) -> [DayFoodSummary] {
        let calendar = Calendar.current
        let mealsByDay = Dictionary(grouping: meals) { $0.date.startOfDay }
        guard let earliestLogged = mealsByDay.keys.min(),
              let latestLogged = mealsByDay.keys.max() else { return [] }

        let todayStart = today.startOfDay
        let end = max(todayStart, latestLogged)
        let windowStart = days
            .flatMap { calendar.date(byAdding: .day, value: -(max(1, $0) - 1), to: end) }
            .map { calendar.startOfDay(for: $0) } ?? earliestLogged
        // Never runs past the first day anything was logged: empty rows for
        // days before the user even had the app say nothing useful.
        let start = max(windowStart, earliestLogged)
        guard start <= end else { return [] }

        // Everything below that isn't per-day is computed once. estimateMaintenance
        // in particular walks the whole meal and weight history.
        let maintenance = settings.map {
            Analytics.estimateMaintenance(settings: $0, weights: weights, meals: meals, steps: steps)
        } ?? 2400
        let baseTarget = goal?.calorieTarget ?? maintenance
        let bodyWeightKg = WeightTrendCalculator.currentTrendKg(entries: weights) ?? weights.last?.weightKg ?? 70
        let applyTEF = settings?.applyTEF ?? true
        let portionUplift = (settings?.portionEstimationAdjustment ?? .off).uplift
        let sickAllowance = (settings?.isSickToday ?? false) ? SickDayAdjustment.calorieAllowance : 0

        var summaries: [DayFoodSummary] = []
        var day = end
        // Bounded so a corrupt future-dated entry can't spin this forever.
        while day >= start, summaries.count < 800 {
            let dayMeals = (mealsByDay[day] ?? []).sorted { $0.date < $1.date }
            let nutrition = DailyNutritionCalculator.summary(for: day, meals: dayMeals)
            let activity = ActivityAdjustmentCalculator.summary(
                for: day, steps: steps, activeEnergy: activeEnergy, workouts: workouts,
                adjustment: .full, bodyWeightKg: bodyWeightKg)
            let tef = applyTEF
                ? NutritionCalculator.tef(protein: nutrition.protein, carbs: nutrition.carbs, fat: nutrition.fat)
                : 0
            let calories = CalorieRemainingCalculator.summary(
                baseTarget: baseTarget + (day == todayStart ? sickAllowance : 0),
                nutrition: nutrition,
                activityAdjustment: activity,
                tefCalories: tef,
                portionUplift: portionUplift)
            summaries.append(DayFoodSummary(date: day, meals: dayMeals,
                                            nutrition: nutrition, calories: calories))
            // Re-normalized rather than just stepped: in the zones where a
            // DST change lands at midnight, "one day earlier" isn't the
            // previous start-of-day, and the day's meals are keyed by exactly
            // that.
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = calendar.startOfDay(for: previous)
        }
        return summaries
    }

    /// Headline figures for a stretch of history: only days with something
    /// logged count toward the averages, so a week with three logged days
    /// averages those three rather than being diluted by the untracked ones.
    static func averages(_ summaries: [DayFoodSummary]) -> (loggedDays: Int, calories: Double, protein: Double)? {
        let logged = summaries.filter { !$0.isEmpty }
        guard !logged.isEmpty else { return nil }
        let count = Double(logged.count)
        return (logged.count,
                logged.reduce(0) { $0 + $1.calories.eaten } / count,
                logged.reduce(0) { $0 + $1.nutrition.protein } / count)
    }
}
