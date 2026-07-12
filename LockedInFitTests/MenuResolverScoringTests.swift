import XCTest
@testable import LockedInFit

/// Resolver behaviour (official vs estimated) and Health/Satiety recalculation.
final class MenuResolverScoringTests: XCTestCase {

    private func component(_ name: String, grams: Double, method: CookingMethod? = nil) -> MenuItemComponent {
        let p = FoodNutritionTable.all.first { $0.canonicalName == name }!
        return MenuItemComponent(name: p.canonicalName, kind: p.kind, grams: grams,
                                 base: p.per100g * (grams / 100),
                                 cookingMethod: method ?? p.defaultMethod)
    }

    private func officialItem() -> MenuItem {
        let r = SampleMenuData.restaurants.first { $0.id == "sample:burgerbarn" }!
        let items = SampleMenuData.menu(for: r)
        return items.first { $0.sourceKind == .official && $0.officialNutrition != nil }!
    }

    private func estimatedFriedItem() -> MenuItem {
        let r = SampleMenuData.restaurants.first { $0.id == "sample:brooklynburger" }!
        let items = SampleMenuData.menu(for: r)
        return items.first { $0.name.contains("Fries") }!
    }

    // MARK: Official nutrition is never modified by our oil estimates

    func testOfficialNutritionNotChangedByOilOverride() {
        let item = officialItem()
        let official = item.officialNutrition!
        let base = MenuItemResolver.resolve(item: item)
        XCTAssertEqual(base.perUnit.calories, official.calories, accuracy: 0.001,
                       "Official calories must be shown verbatim")

        var heavy = ItemConfiguration()
        heavy.oilLevelOverride = .heavy
        let oiled = MenuItemResolver.resolve(item: item, config: heavy)
        XCTAssertEqual(oiled.perUnit.calories, official.calories, accuracy: 0.001,
                       "Oil override must not touch official nutrition (no double count)")
        XCTAssertEqual(oiled.perUnit.fat, official.fat, accuracy: 0.001)
        XCTAssertEqual(oiled.breakdown.oilCalories, 0, accuracy: 0.001)
    }

    func testOfficialItemReportsOfficialSource() {
        XCTAssertEqual(MenuItemResolver.resolve(item: officialItem()).sourceKind, .official)
    }

    // MARK: Health Score recalculates with composition

    func testHealthScoreDropsWhenAddingSugaryDrink() {
        let chicken = component("Chicken breast", grams: 170, method: .grilled)
        let broccoli = component("Broccoli", grams: 120, method: .steamed)
        let baseNutrition = chicken.base + broccoli.base
        let baseScore = MenuHealthScoreCalculator.score(nutrition: baseNutrition,
                                                        components: [chicken, broccoli],
                                                        sourceKind: .estimatedFromIngredients).score

        let soda = component("Regular soda", grams: 330)
        let withSoda = baseNutrition + soda.base
        let sodaScore = MenuHealthScoreCalculator.score(nutrition: withSoda,
                                                       components: [chicken, broccoli, soda],
                                                       sourceKind: .estimatedFromIngredients).score
        XCTAssertLessThan(sodaScore, baseScore, "Adding a sugary drink should lower the Health Score")
    }

    func testHealthScoreRecalculatesWithOilLevel() {
        let item = estimatedFriedItem()
        var none = ItemConfiguration(); none.oilLevelOverride = .none
        var heavy = ItemConfiguration(); heavy.oilLevelOverride = .heavy
        let low = MenuItemResolver.resolve(item: item, config: none)
        let high = MenuItemResolver.resolve(item: item, config: heavy)
        XCTAssertGreaterThan(high.perUnit.calories, low.perUnit.calories, "Heavy oil should add calories")
        XCTAssertLessThanOrEqual(high.healthScore, low.healthScore, "More oil should not improve the Health Score")
    }

    // MARK: Satiety Score recalculates

    func testSatietyLowerForLiquidCalories() {
        let chicken = component("Chicken breast", grams: 170, method: .grilled)
        let rice = component("White rice", grams: 200, method: .steamed)
        let solid = chicken.base + rice.base
        let solidScore = SatietyScoreCalculator.score(nutrition: solid, components: [chicken, rice]).score

        let soda = component("Regular soda", grams: 500)
        let smoothie = component("Smoothie", grams: 400)
        let liquid = soda.base + smoothie.base
        let liquidScore = SatietyScoreCalculator.score(nutrition: liquid, components: [soda, smoothie]).score
        XCTAssertGreaterThan(solidScore, liquidScore, "A solid protein+carb meal should be more filling than liquid calories")
    }

    func testSatietyRecalculatesWhenAddingFibreVolume() {
        let base = component("White rice", grams: 150, method: .steamed)
        let s1 = SatietyScoreCalculator.score(nutrition: base.base, components: [base]).score
        let broccoli = component("Broccoli", grams: 200, method: .steamed)
        let chicken = component("Chicken breast", grams: 150, method: .grilled)
        let bigger = base.base + broccoli.base + chicken.base
        let s2 = SatietyScoreCalculator.score(nutrition: bigger, components: [base, broccoli, chicken]).score
        XCTAssertGreaterThan(s2, s1, "Adding high-protein, high-volume food should raise satiety per calorie")
    }

    // MARK: Estimated items are rounded (no fake precision)

    func testEstimatedCaloriesAreRounded() {
        let resolved = MenuItemResolver.resolve(item: estimatedFriedItem())
        let cals = resolved.perUnit.calories
        XCTAssertEqual(cals, (cals / 5).rounded() * 5, accuracy: 0.001, "Estimated calories should be rounded to a 5/10 step")
    }
}
