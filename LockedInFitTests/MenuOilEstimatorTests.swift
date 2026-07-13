import XCTest
@testable import LockedInFit

/// The absolute oil rule and cooking-method oil behaviour.
final class MenuOilEstimatorTests: XCTestCase {

    // MARK: Steamed → exactly zero, at any level and portion

    func testSteamedAlwaysZeroOil() {
        for level in OilLevel.allCases {
            for grams in [50.0, 200.0, 600.0] {
                let e = MenuOilEstimator.estimate(foodName: "broccoli", method: .steamed, grams: grams, level: level)
                XCTAssertEqual(e.calories, 0, "Steamed must be 0 oil kcal at \(level) / \(grams)g")
                XCTAssertEqual(e.grams, 0, "Steamed must be 0 oil grams at \(level) / \(grams)g")
            }
        }
    }

    func testSteamedZeroEvenWithHeavyOilLevelAndCustomGrams() {
        let e = MenuOilEstimator.estimate(foodName: "fish", method: .steamed, grams: 300, level: .custom, customGrams: 40)
        XCTAssertEqual(e.calories, 0)
        XCTAssertEqual(e.grams, 0)
    }

    // MARK: Raw → exactly zero

    func testRawAlwaysZeroOil() {
        for name in ["salmon sashimi", "salad leaves", "cucumber"] {
            let e = MenuOilEstimator.estimate(foodName: name, method: .raw, grams: 150, level: .heavy)
            XCTAssertEqual(e.calories, 0, "Raw \(name) must be 0 oil kcal")
            XCTAssertEqual(e.grams, 0, "Raw \(name) must be 0 oil grams")
        }
    }

    // MARK: Other methods do get oil (grilled never auto-zero)

    func testGrilledIsNotAutoZero() {
        let e = MenuOilEstimator.estimate(foodName: "chicken breast", method: .grilled, grams: 170, level: .standard)
        XCTAssertGreaterThan(e.calories, 0, "Grilled should account for marinade/finishing oil")
    }

    func testDeepFriedBreadedAbsorbsMoreThanPlain() {
        let breaded = MenuOilEstimator.estimate(foodName: "breaded chicken katsu", method: .deepFried, grams: 160)
        let plain = MenuOilEstimator.estimate(foodName: "chicken", method: .grilled, grams: 160)
        XCTAssertGreaterThan(breaded.calories, plain.calories)
    }

    func testOilNoneOverridesMethodDefault() {
        let e = MenuOilEstimator.estimate(foodName: "stir fried chicken", method: .stirFried, grams: 200, level: .none)
        XCTAssertEqual(e.calories, 0)
    }

    func testSauceComponentGetsNoCookingOil() {
        // A sauce carries its own fat; cooking oil must not be added on top.
        let e = MenuOilEstimator.estimate(foodName: "vinaigrette", method: .unknown, grams: 40, level: .standard, carriesOwnFat: true)
        XCTAssertEqual(e.calories, 0)
        XCTAssertEqual(e.grams, 0)
    }

    // MARK: Raw salad with dressing: dressing counted separately, salad zero

    func testRawSaladWithDressingCountsDressingSeparately() {
        let est = MenuNutritionEstimator.estimate(name: "Garden Salad",
                                                  description: "salad greens, tomato with vinaigrette dressing")
        let item = MenuItem(restaurantID: "t", name: "Garden Salad", category: .salads, components: est.components)
        let resolved = MenuItemResolver.resolve(item: item)
        // No cooking oil should be added (greens are raw; dressing carries own fat).
        XCTAssertEqual(resolved.breakdown.oilCalories, 0, accuracy: 0.001,
                       "Raw salad must not add cooking oil")
        // But the dressing's own fat must still be present in the totals.
        XCTAssertGreaterThan(resolved.perUnit.fat, 5, "Dressing fat should be counted separately")
        XCTAssertTrue(resolved.breakdown.componentLines.contains { $0.label.lowercased().contains("vinaigrette") })
    }

    // MARK: Steamed fish with chilli oil: chilli oil counted, no cooking oil

    func testSteamedFishWithChilliOilCountsChilliOilOnly() {
        let est = MenuNutritionEstimator.estimate(name: "Steamed Fish with Chilli Oil",
                                                  description: "steamed white fish topped with chilli oil")
        let item = MenuItem(restaurantID: "t", name: "Steamed Fish with Chilli Oil", category: .mains, components: est.components)
        let resolved = MenuItemResolver.resolve(item: item)
        // Zero cooking oil for the steaming...
        XCTAssertEqual(resolved.breakdown.oilCalories, 0, accuracy: 0.001,
                       "Steaming adds no cooking oil")
        // ...but the chilli oil's own fat is included.
        XCTAssertTrue(resolved.breakdown.componentLines.contains { $0.label.lowercased().contains("chili oil") },
                      "Chilli oil should appear as its own component")
        XCTAssertGreaterThan(resolved.perUnit.fat, 8, "Chilli oil fat should be counted")
    }
}
