import XCTest
@testable import LockedInFit

/// The Add Meal preset cart: staging several preset foods, each with its own
/// portion, and turning the whole cart into the meal's FoodItems in one pass.
@MainActor
final class PresetCartTests: XCTestCase {

    private func preset(name: String = "Chicken breast", serving: String = "100 g",
                        referenceGrams: Double = 100, calories: Double = 165,
                        protein: Double = 31, carbs: Double = 0, fat: Double = 3.6,
                        fiber: Double = 0, sodium: Double = 74) -> FoodPreset {
        FoodPreset(name: name, serving: serving, referenceGrams: referenceGrams,
                   calories: calories, protein: protein, carbs: carbs, fat: fat,
                   fiber: fiber, sodium: sodium)
    }

    private func gramLine(_ p: FoodPreset, grams: Double, weighed: Bool = false) -> PresetCartLine {
        let reference = p.effectiveReferenceGrams
        return PresetCartLine(preset: p,
                              portion: PresetPortion(grams: grams,
                                                     ratio: reference > 0 ? grams / reference : 1,
                                                     weighed: weighed))
    }

    private func servingLine(_ p: FoodPreset, servings: Double) -> PresetCartLine {
        let reference = p.effectiveReferenceGrams
        return PresetCartLine(preset: p,
                              portion: PresetPortion(grams: reference > 0 ? servings * reference : 0,
                                                     ratio: servings, servings: servings))
    }

    // MARK: totals

    func testTotalsSumEveryLine() {
        let chicken = preset()
        let rice = preset(name: "White rice", calories: 130, protein: 2.7, carbs: 28,
                          fat: 0.3, fiber: 0.4, sodium: 1)
        let totals = PresetCartMath.totals(for: [gramLine(chicken, grams: 200),
                                                 gramLine(rice, grams: 150)])
        XCTAssertEqual(totals.itemCount, 2)
        XCTAssertEqual(totals.calories, 165 * 2 + 130 * 1.5, accuracy: 0.001)
        XCTAssertEqual(totals.protein, 31 * 2 + 2.7 * 1.5, accuracy: 0.001)
        XCTAssertEqual(totals.carbs, 28 * 1.5, accuracy: 0.001)
        XCTAssertEqual(totals.fat, 3.6 * 2 + 0.3 * 1.5, accuracy: 0.001)
        XCTAssertEqual(totals.fiber, 0.4 * 1.5, accuracy: 0.001)
        XCTAssertEqual(totals.sodium, 74 * 2 + 1 * 1.5, accuracy: 0.001)
    }

    func testEmptyCartTotalsAreZero() {
        XCTAssertEqual(PresetCartMath.totals(for: []), PresetCartTotals())
    }

    func testSamePresetTwiceStaysTwoLines() {
        // Two helpings of the same food are usually two different portions,
        // so the cart keeps them apart instead of merging them.
        let egg = preset(name: "Hardboiled egg", serving: "1 egg", referenceGrams: 50,
                         calories: 78, protein: 6, carbs: 0.6, fat: 5)
        let totals = PresetCartMath.totals(for: [servingLine(egg, servings: 2),
                                                 servingLine(egg, servings: 1)])
        XCTAssertEqual(totals.itemCount, 2)
        XCTAssertEqual(totals.calories, 78 * 3, accuracy: 0.001)
    }

    // MARK: makeFoodItem

    func testGramLineScalesNutritionToTheWeightItRecords() {
        // The recorded grams and the scaled nutrition must describe the same
        // amount of food: FoodItemEditorRow rescales from that starting pair,
        // so a mismatch throws off every later edit by the same wrong ratio.
        let item = gramLine(preset(), grams: 250).makeFoodItem(order: 0)
        XCTAssertEqual(item.grams, 250)
        XCTAssertEqual(item.calories, 165 * 2.5, accuracy: 0.001)
        XCTAssertEqual(item.protein, 31 * 2.5, accuracy: 0.001)
        XCTAssertTrue(item.fromPreset)
        XCTAssertFalse(item.weighed)
    }

    func testWeighedFlagSurvivesIntoTheFoodItem() {
        let item = gramLine(preset(), grams: 120, weighed: true).makeFoodItem(order: 0)
        XCTAssertTrue(item.weighed)
    }

    func testServingLineWithNoReferenceWeightAppliesSavedNutritionAsIs() {
        // A "1 meal" preset has no gram basis; one serving must be its saved
        // numbers exactly, and the item must not claim a weight it never had.
        let bowl = preset(name: "Chipotle Bowl", serving: "1 meal", referenceGrams: 0,
                          calories: 600, protein: 45, carbs: 60, fat: 20)
        let item = servingLine(bowl, servings: 1).makeFoodItem(order: 0)
        XCTAssertEqual(item.calories, 600, accuracy: 0.001)
        XCTAssertEqual(item.protein, 45, accuracy: 0.001)
        XCTAssertEqual(item.grams, 0)
    }

    func testFoodItemsContinueTheMealsExistingOrder() {
        // Carting foods after a photo/speech/manual pass must append, not
        // reshuffle: MealLog.items sorts on `order`.
        let items = PresetCartMath.foodItems(for: [gramLine(preset(), grams: 100),
                                                   gramLine(preset(name: "Rice"), grams: 100)],
                                             startingAt: 3)
        XCTAssertEqual(items.map(\.order), [3, 4])
    }

    // MARK: amountDescription

    func testGramAmountReadsAsAWeight() {
        XCTAssertEqual(gramLine(preset(), grams: 180).amountDescription, "180 g")
    }

    func testServingAmountReadsAsACountOfTheSavedServing() {
        let egg = preset(name: "Hardboiled egg", serving: "1 egg", referenceGrams: 50,
                         calories: 78, protein: 6, carbs: 0.6, fat: 5)
        XCTAssertEqual(servingLine(egg, servings: 2).amountDescription, "2 × 1 egg · 100 g")
        XCTAssertEqual(servingLine(egg, servings: 0.5).amountDescription, "0.5 × 1 egg · 25 g")
    }

    func testServingAmountWithNoWeightOmitsGrams() {
        let bowl = preset(name: "Chipotle Bowl", serving: "1 meal", referenceGrams: 0,
                          calories: 600, protein: 45, carbs: 60, fat: 20)
        XCTAssertEqual(servingLine(bowl, servings: 1).amountDescription, "1 × 1 meal")
    }
}
