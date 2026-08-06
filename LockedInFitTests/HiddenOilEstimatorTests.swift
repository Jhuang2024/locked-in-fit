import XCTest
import SwiftData
@testable import LockedInFit

/// The hidden-oil estimator behind manually and photo-logged meals: which
/// foods are charged oil calories they never had, and what the meal row
/// actually reports.
@MainActor
final class HiddenOilEstimatorTests: XCTestCase {

    private func range(_ name: String, _ method: CookingMethod, grams: Double = 150)
    -> (low: Double, high: Double) {
        HiddenOilEstimator.range(for: name, method: method, grams: grams)
    }

    // MARK: zero-oil methods

    func testRawFoodGetsExactlyZeroOil() {
        // An apple used to be charged 0-9 kcal of cooking oil.
        let apple = range("apple", .raw, grams: 180)
        XCTAssertEqual(apple.low, 0)
        XCTAssertEqual(apple.high, 0)
    }

    func testSteamedBoiledAndPoachedGetExactlyZeroOil() {
        for method in [CookingMethod.steamed, .boiled, .poached, .raw] {
            let r = range("corn", method, grams: 300)
            XCTAssertEqual(r.high, 0, "\(method.rawValue) should add no oil")
            XCTAssertEqual(r.low, 0, "\(method.rawValue) should add no oil")
        }
    }

    func testZeroOilMethodBeatsFoodNameModifiers() {
        // The name modifiers used to run regardless of method, so a *boiled*
        // rice noodle was handed a stir-fried noodle's oil budget, and steamed
        // eggplant was treated as an oil sponge.
        XCTAssertEqual(range("boiled rice noodles", .boiled).high, 0)
        XCTAssertEqual(range("steamed eggplant", .steamed).high, 0)
        XCTAssertEqual(range("steamed tofu", .steamed).high, 0)
    }

    func testUnstatedMethodIsReadOffTheFoodName() {
        // The AI doesn't always fill in a cooking method. When the name says
        // it plainly, that's the method, not "unknown, assume oil".
        XCTAssertEqual(range("steamed corn", .unknown).high, 0)
        XCTAssertEqual(range("boiled rice noodles", .unknown).high, 0)
        XCTAssertEqual(range("raw salmon", .unknown).high, 0)
    }

    // MARK: methods that do add oil

    func testOilyMethodsAreUnchanged() {
        let stirFried = range("green beans", .stirFried)
        XCTAssertEqual(stirFried.low, 30, accuracy: 0.001)
        XCTAssertEqual(stirFried.high, 95, accuracy: 0.001)
        let deepFried = range("chicken", .deepFried)
        XCTAssertEqual(deepFried.low, 70, accuracy: 0.001)
        XCTAssertEqual(deepFried.high, 160, accuracy: 0.001)
    }

    func testEggplantIsStillAnOilSpongeWhenItIsActuallyCooked() {
        let r = range("stir-fried eggplant", .stirFried)
        XCTAssertEqual(r.low, 45, accuracy: 0.001)
        XCTAssertEqual(r.high, 145, accuracy: 0.001)
    }

    func testGenuinelyUnknownPrepStillAssumesOil() {
        // Nothing in "beef mince sauce" says how it was cooked, so the
        // unknown-prep assumption must survive the name-parsing shortcut.
        let r = range("beef mince sauce", .unknown)
        XCTAssertGreaterThan(r.high, 0)
    }

    func testPortionScaling() {
        let small = range("chicken", .deepFried, grams: 75)
        let large = range("chicken", .deepFried, grams: 300)
        XCTAssertEqual(small.high, 160 * 0.5, accuracy: 0.001)
        XCTAssertEqual(large.high, 160 * 2.0, accuracy: 0.001)
    }

    // MARK: whole-meal totals

    func testAMealOfSteamedAndBoiledFoodCarriesNoOilAtAll() {
        let items = [FoodItem(name: "steamed corn", grams: 200, calories: 180, cookingMethod: .steamed),
                     FoodItem(name: "boiled rice noodles", grams: 250, calories: 300, cookingMethod: .boiled),
                     FoodItem(name: "grapes", grams: 120, calories: 80, cookingMethod: .raw)]
        let oil = HiddenOilEstimator.estimate(forFoodItems: items)
        XCTAssertEqual(oil.low, 0)
        XCTAssertEqual(oil.high, 0)
    }

    // MARK: what gets reported

    func testCountedLabelLeadsWithTheFigureThatIsActuallyApplied() {
        // The midpoint is what MealLog.hiddenOilCalories adds to the day, so
        // it has to be on screen, not just the range around it.
        XCTAssertEqual(HiddenOilEstimator.countedLabel(low: 0, high: 26),
                       "Oil +13 kcal counted (range 0–26)")
        XCTAssertEqual(HiddenOilEstimator.countedLabel(low: 16, high: 85),
                       "Oil +51 kcal counted (range 16–85)")
    }

    func testCountedLabelIsAbsentWhenThereIsNoOil() {
        XCTAssertNil(HiddenOilEstimator.countedLabel(low: 0, high: 0))
    }

    func testZeroOilMethodsReadAsNoAddedOil() {
        XCTAssertEqual(HiddenOilEstimator.riskLabel(for: .steamed), "No added oil")
        XCTAssertEqual(HiddenOilEstimator.riskLabel(for: .raw), "No added oil")
        XCTAssertEqual(HiddenOilEstimator.riskLabel(for: .deepFried), "Very high oil risk")
    }
}

/// Repairing hidden oil already stored on logged meals. The numbers live on
/// the meal, so fixing the estimator alone leaves history reading wrong.
@MainActor
final class HiddenOilBackfillTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MealLog.self, FoodItem.self, configurations: config)
        return ModelContext(container)
    }

    private func insertMeal(_ context: ModelContext, items: [FoodItem],
                            calories: Double, oilLow: Double, oilHigh: Double) -> MealLog {
        let meal = MealLog(calories: calories, calorieHigh: calories * 1.1 + oilHigh,
                           hiddenOilLow: oilLow, hiddenOilHigh: oilHigh, foodItems: items)
        context.insert(meal)
        return meal
    }

    func testPhantomOilOnRawAndSteamedFoodIsZeroedOut() throws {
        let context = try makeContext()
        let meal = insertMeal(context,
                              items: [FoodItem(name: "apple", grams: 180, calories: 95, cookingMethod: .raw)],
                              calories: 95, oilLow: 0, oilHigh: 9)
        let result = HiddenOilBackfill.repair([meal])
        XCTAssertEqual(result.repaired, 1)
        XCTAssertEqual(meal.hiddenOilLow, 0)
        XCTAssertEqual(meal.hiddenOilHigh, 0)
        XCTAssertEqual(meal.hiddenOilCalories, 0)
        // The calorie ceiling was carrying the same phantom oil.
        XCTAssertEqual(meal.calorieHigh, (95 * 1.1).rounded())
        XCTAssertEqual(result.reclaimed, 4.5, accuracy: 0.001)
    }

    func testMealsWithRealOilAreLeftAlone() throws {
        let context = try makeContext()
        let meal = insertMeal(context,
                              items: [FoodItem(name: "chicken", grams: 150, calories: 400, cookingMethod: .deepFried)],
                              calories: 400, oilLow: 70, oilHigh: 160)
        let result = HiddenOilBackfill.repair([meal])
        XCTAssertEqual(result.repaired, 0)
        XCTAssertEqual(meal.hiddenOilLow, 70)
        XCTAssertEqual(meal.hiddenOilHigh, 160)
    }

    func testMealsWithoutItemizedFoodAreNeverTouched() throws {
        // Nothing to re-derive oil from: zeroing these would delete a real
        // estimate rather than correct a wrong one.
        let context = try makeContext()
        let meal = insertMeal(context, items: [], calories: 620, oilLow: 80, oilHigh: 260)
        let result = HiddenOilBackfill.repair([meal])
        XCTAssertEqual(result.repaired, 0)
        XCTAssertEqual(meal.hiddenOilLow, 80)
        XCTAssertEqual(meal.hiddenOilHigh, 260)
    }

    func testMixedMealKeepsOnlyTheOilItsCookedFoodEarns() throws {
        let context = try makeContext()
        let meal = insertMeal(context, items: [
            FoodItem(name: "steamed corn", grams: 150, calories: 130, cookingMethod: .steamed),
            FoodItem(name: "stir-fried greens", grams: 150, calories: 90, cookingMethod: .stirFried),
        ], calories: 220, oilLow: 38, oilHigh: 103)
        HiddenOilBackfill.repair([meal])
        XCTAssertEqual(meal.hiddenOilLow, 30)
        XCTAssertEqual(meal.hiddenOilHigh, 95)
    }
}
