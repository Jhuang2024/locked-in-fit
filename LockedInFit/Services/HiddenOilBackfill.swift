import Foundation
import SwiftData

/// One-time repair of hidden-oil figures already written into logged meals.
///
/// Hidden oil is stored on the meal, not recomputed on display, so fixing the
/// estimator doesn't fix history: an apple logged before the fix keeps reading
/// "Oil +0-9 kcal" forever, and keeps quietly spending that many calories out
/// of the day's target. This recomputes each meal's oil from its own food
/// items with the corrected estimator (raw/steamed/boiled/poached are exactly
/// zero, and food-name modifiers no longer override that).
///
/// Deliberately narrow, because these numbers are the user's data:
/// - Only meals that itemize their food are touched. A meal logged as bare
///   totals has no items to re-derive oil from, and zeroing it would delete a
///   real estimate rather than correct a wrong one.
/// - Only meals whose numbers actually change are written.
/// - It runs exactly once. The hidden-oil fields are user-editable in the meal
///   detail screen, so a pass on every launch would silently overwrite a
///   deliberate manual figure every time the app started.
/// - The "already ran" flag is only set once a store with meals in it has been
///   seen, so the empty-store auto-restore path (see
///   `BackupService.autoRestoreOnEmptyLaunch`) doesn't spend the one pass on
///   nothing and leave the restored meals unrepaired.
enum HiddenOilBackfill {
    private static let defaultsKey = "hiddenOilBackfill.zeroOilMethods.v1"

    @MainActor
    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }
        guard let meals = try? context.fetch(FetchDescriptor<MealLog>()), !meals.isEmpty else { return }
        let result = repair(meals)
        UserDefaults.standard.set(true, forKey: defaultsKey)
        PerfLog.event("hiddenOilBackfill.repaired: \(result.repaired) meals, \(Int(result.reclaimed)) kcal")
    }

    /// The repair itself, without the run-once gate: how many meals changed and
    /// how many phantom oil calories that handed back to the user's day.
    @discardableResult
    static func repair(_ meals: [MealLog]) -> (repaired: Int, reclaimed: Double) {
        var repaired = 0
        var reclaimed = 0.0
        for meal in meals {
            let items = meal.items
            guard !items.isEmpty else { continue }
            let oil = HiddenOilEstimator.estimate(forFoodItems: items)
            let low = oil.low.rounded()
            let high = oil.high.rounded()
            guard low != meal.hiddenOilLow || high != meal.hiddenOilHigh else { continue }
            reclaimed += meal.hiddenOilCalories - (low + high) / 2
            meal.hiddenOilLow = low
            meal.hiddenOilHigh = high
            // Keep the calorie ceiling coherent with the oil feeding it: same
            // formula the meal editor applies whenever a food item is edited.
            meal.calorieHigh = (meal.calories * 1.1 + high).rounded()
            repaired += 1
        }
        return (repaired, reclaimed)
    }
}
