import XCTest
@testable import LockedInFit

/// Natural-language meal parsing, including the shared oil rules.
final class MealSpeechParserTests: XCTestCase {

    private func entry(_ preview: ParsedMealPreview, named name: String) -> ParsedMealEntry? {
        preview.entries.first { $0.name == name }
    }

    func testSteamedAndRawSpokenMealHasZeroOil() {
        let preview = MealSpeechParser.parse("I had steamed fish, one bowl of rice, and some raw cucumber")
        let fish = entry(preview, named: "White fish")
        let rice = entry(preview, named: "White rice")
        let cucumber = entry(preview, named: "Cucumber")
        XCTAssertNotNil(fish); XCTAssertNotNil(rice); XCTAssertNotNil(cucumber)
        XCTAssertEqual(fish?.oilCalories, 0, "Steamed fish → zero added oil")
        XCTAssertEqual(rice?.oilCalories, 0, "Steamed rice → zero added oil")
        XCTAssertEqual(cucumber?.oilCalories, 0, "Raw cucumber → zero added oil")
    }

    func testNoOilPhraseOverridesGrilledOil() {
        let withOil = MealSpeechParser.parse("grilled chicken")
        let noOil = MealSpeechParser.parse("grilled chicken with no oil")
        XCTAssertGreaterThan(entry(withOil, named: "Chicken breast")?.oilCalories ?? 0, 0,
                             "Grilled without instruction should assume some oil")
        XCTAssertEqual(entry(noOil, named: "Chicken breast")?.oilCalories, 0,
                       "\"no oil\" must force zero added oil")
    }

    func testQuantityScalesPortion() {
        let preview = MealSpeechParser.parse("two scrambled eggs, two pieces of toast with a little butter, and a medium banana")
        let egg = entry(preview, named: "Egg")
        XCTAssertNotNil(egg)
        XCTAssertEqual(egg?.grams ?? 0, 200, accuracy: 1, "Two eggs ≈ 200 g")
        XCTAssertNotNil(entry(preview, named: "Butter"), "Butter should be parsed")
    }

    func testBrandDetectionAndDietSoda() {
        let preview = MealSpeechParser.parse("three slices of pepperoni pizza from Domino's and drank a can of Coke Zero")
        XCTAssertTrue(preview.mentionedBrands.contains { $0.lowercased().contains("domino") },
                      "Should surface the mentioned brand")
        let diet = entry(preview, named: "Diet soda")
        XCTAssertNotNil(diet, "Coke Zero should map to a zero-calorie drink")
        XCTAssertLessThan(diet?.nutrition.calories ?? 99, 5, "Diet soda should be ~0 kcal")
    }

    func testMealTypeDetectedFromPhrase() {
        let preview = MealSpeechParser.parse("for lunch I had a grilled chicken burrito bowl")
        XCTAssertEqual(preview.mealType, .lunch)
    }

    func testUnparseableTermsFlaggedUncertain() {
        let preview = MealSpeechParser.parse("I ate a bowl of xyzzy stew")
        // "xyzzy" isn't a known food; it should be flagged, not silently dropped.
        XCTAssertTrue(preview.uncertainTerms.contains { $0.lowercased().contains("xyzzy") }
                      || preview.entries.contains { $0.isUncertain })
    }
}
