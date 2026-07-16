import XCTest
@testable import LockedInFit

/// Portion semantics of food presets: what the reference weight parse
/// accepts, and which foods count in servings instead of grams (the two
/// inputs behind the Add Meal "How Much?" step).
@MainActor
final class PresetPortionTests: XCTestCase {

    private func preset(name: String = "Food", serving: String,
                        referenceGrams: Double = 0) -> FoodPreset {
        FoodPreset(name: name, serving: serving, referenceGrams: referenceGrams,
                   calories: 100, protein: 10, carbs: 10, fat: 3)
    }

    // MARK: effectiveReferenceGrams

    func testExplicitReferenceGramsWins() {
        XCTAssertEqual(preset(serving: "1 bowl", referenceGrams: 250).effectiveReferenceGrams, 250)
    }

    func testParsesMassAndVolumeServingLabels() {
        XCTAssertEqual(preset(serving: "150 g").effectiveReferenceGrams, 150)
        XCTAssertEqual(preset(serving: "150g").effectiveReferenceGrams, 150)
        XCTAssertEqual(preset(serving: "330 ml").effectiveReferenceGrams, 330)
        XCTAssertEqual(preset(serving: "180 g cooked").effectiveReferenceGrams, 180)
    }

    func testCountStyleServingIsNotOneGram() {
        // Menu Checker's saved meals use "1 meal": reading that as a
        // 1-gram reference would multiply the meal's calories by whatever
        // gram amount the user enters. It must read as unknown instead.
        XCTAssertEqual(preset(serving: "1 meal").effectiveReferenceGrams, 0)
        XCTAssertEqual(preset(serving: "2 slices").effectiveReferenceGrams, 0)
        XCTAssertEqual(preset(serving: "1 bowl").effectiveReferenceGrams, 0)
        XCTAssertEqual(preset(serving: "one bowl").effectiveReferenceGrams, 0)
        XCTAssertEqual(preset(serving: "").effectiveReferenceGrams, 0)
    }

    // MARK: isCountedInServings

    func testCountStyleServingLabelCountsInServings() {
        XCTAssertTrue(preset(serving: "1 meal").isCountedInServings)
        XCTAssertTrue(preset(serving: "2 slices").isCountedInServings)
    }

    func testCountableFoodNamesCountInServings() {
        XCTAssertTrue(preset(name: "hardboiled egg", serving: "50 g").isCountedInServings)
        XCTAssertTrue(preset(name: "Hardboiled Eggs", serving: "100 g").isCountedInServings)
        XCTAssertTrue(preset(name: "popsicle", serving: "100 g").isCountedInServings)
        XCTAssertTrue(preset(name: "beef cutlet", serving: "120 g").isCountedInServings)
    }

    func testBulkFoodsStayGramFirst() {
        XCTAssertFalse(preset(name: "boiled noodles", serving: "250 g").isCountedInServings)
        XCTAssertFalse(preset(name: "grilled chicken breast", serving: "400 g").isCountedInServings)
        XCTAssertFalse(preset(name: "celery", serving: "100 g").isCountedInServings)
        // Whole-word matching: "bar" must not hide inside "barbecue".
        XCTAssertFalse(preset(name: "barbecue pork", serving: "200 g").isCountedInServings)
    }

    // MARK: preset substitution safety (the "1 meal" scaling bug)

    func testMealPresetSubstitutionNeverScalesByGrams() {
        // An AI estimate matching a saved "1 meal" preset used to scale the
        // preset's calories by grams / 1 (the bogus 1-gram reference),
        // inflating a 600 kcal meal to hundreds of thousands. With the
        // reference unknown, the saved numbers must be used as-is.
        let saved = FoodPreset(name: "Chipotle Bowl", serving: "1 meal",
                               calories: 600, protein: 45, carbs: 60, fat: 20)
        let estimate = MealEstimate.FoodItemEstimate(
            name: "Chipotle Bowl", grams: 550, calories: 700, protein: 40,
            carbs: 70, fat: 25, fiber: 8, sodium: 900,
            cookingMethod: "unknown", confidence: 0.7)
        let item = estimate.makeFoodItem(presets: [saved])
        XCTAssertEqual(item.calories, 600)
        XCTAssertEqual(item.protein, 45)
        XCTAssertEqual(item.grams, 550)
    }
}
