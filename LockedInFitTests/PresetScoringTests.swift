import XCTest
@testable import LockedInFit

/// Preset Health/Satiety scoring and restaurant menu-score enrichment: the
/// pieces behind the "sort by Health/Satiety Score" controls.
@MainActor
final class PresetScoringTests: XCTestCase {

    // MARK: Preset scores

    func testLeanProteinOutscoresSugaryDrink() {
        let chicken = FoodPreset(name: "Grilled Chicken Breast", serving: "150 g", referenceGrams: 150,
                                 calories: 240, protein: 45, carbs: 0, fat: 5, fiber: 0, sodium: 110,
                                 cookingMethod: .grilled)
        let soda = FoodPreset(name: "Cola", serving: "330 ml", referenceGrams: 330,
                              calories: 140, protein: 0, carbs: 35, fat: 0, fiber: 0, sodium: 15)

        let chickenScores = PresetScoringService.scores(for: chicken)
        let sodaScores = PresetScoringService.scores(for: soda)
        XCTAssertGreaterThan(chickenScores.health, sodaScores.health)
        XCTAssertGreaterThan(chickenScores.satiety, sodaScores.satiety)
    }

    func testDeepFriedPenalizedAgainstGrilledTwin() {
        // Identical macros; only the cooking method differs.
        let grilled = FoodPreset(name: "Grilled Wings", serving: "200 g", referenceGrams: 200,
                                 calories: 430, protein: 40, carbs: 2, fat: 28, fiber: 0, sodium: 380,
                                 cookingMethod: .grilled)
        let fried = FoodPreset(name: "Fried Wings", serving: "200 g", referenceGrams: 200,
                               calories: 430, protein: 40, carbs: 2, fat: 28, fiber: 0, sodium: 380,
                               cookingMethod: .deepFried)
        XCTAssertGreaterThan(PresetScoringService.scores(for: grilled).health,
                             PresetScoringService.scores(for: fried).health)
    }

    func testMatchesMenuCalculatorsForSameInputs() {
        // A preset must score exactly what the Menu Checker calculators say for
        // the same nutrition/component: no second scoring path.
        let preset = FoodPreset(name: "Salmon Bowl", serving: "400 g", referenceGrams: 400,
                                calories: 560, protein: 38, carbs: 55, fat: 20, fiber: 6, sodium: 700,
                                cookingMethod: .grilled)
        let nutrition = ResolvedNutrition(calories: 560, protein: 38, carbs: 55, fat: 20,
                                          fiber: 6, sodium: 700)
        let component = MenuItemComponent(name: preset.name, kind: .main, grams: 400,
                                          base: nutrition, cookingMethod: .grilled)
        let expectedHealth = MenuHealthScoreCalculator.score(
            nutrition: nutrition, components: [component],
            sourceKind: .estimatedFromIngredients).score
        let expectedSatiety = SatietyScoreCalculator.score(
            nutrition: nutrition, components: [component]).score

        let scores = PresetScoringService.scores(for: preset)
        XCTAssertEqual(scores.health, expectedHealth)
        XCTAssertEqual(scores.satiety, expectedSatiety)
    }

    func testUnknownWeightUsesNeutralDensity() {
        // No reference weight and an unparsable serving label: the synthetic
        // gram estimate must land at the neutral density, not at grams = 0
        // (which would read as absurdly calorie-dense and tank both scores).
        let preset = FoodPreset(name: "Mystery Stew", serving: "one bowl",
                                calories: 400, protein: 25, carbs: 30, fat: 18)
        XCTAssertEqual(preset.effectiveReferenceGrams, 0)
        let scores = PresetScoringService.scores(for: preset)
        let explicit = PresetScoringService.scores(
            for: FoodPreset(name: "Mystery Stew", serving: "one bowl",
                            referenceGrams: 400 / PresetScoringService.neutralCaloriesPerGram,
                            calories: 400, protein: 25, carbs: 30, fat: 18))
        XCTAssertEqual(scores, explicit)
    }

    // MARK: Restaurant enrichment

    func testEnrichFillsScoresForSampleRestaurants() {
        // Sample restaurants' menus are generated locally, so enrichment must
        // fill BOTH averages without any network involvement.
        let withMenu = SampleMenuData.restaurants.filter { !SampleMenuData.menu(for: $0).isEmpty }
        XCTAssertFalse(withMenu.isEmpty)
        let enriched = MenuCheckerRepository.enrichWithMenuScores(withMenu)
        for restaurant in enriched {
            XCTAssertNotNil(restaurant.averageMenuHealthScore, restaurant.name)
            XCTAssertNotNil(restaurant.averageMenuSatietyScore, restaurant.name)
        }
    }

    func testEnrichLeavesUnknownMenusUntouched() {
        // A live restaurant with no cached menu must pass through unchanged
        // rather than getting invented scores.
        var stranger = SampleMenuData.restaurants[0]
        stranger.id = "mapkit:nowhere-to-be-found"
        stranger.averageMenuHealthScore = nil
        stranger.averageMenuSatietyScore = nil
        let enriched = MenuCheckerRepository.enrichWithMenuScores([stranger])
        XCTAssertNil(enriched[0].averageMenuHealthScore)
        XCTAssertNil(enriched[0].averageMenuSatietyScore)
    }

    func testAverageMenuScoresMatchesSingleScoreAverage() {
        let restaurant = SampleMenuData.restaurants[0]
        let items = SampleMenuData.menu(for: restaurant)
        guard let combined = MenuCheckerRepository.averageMenuScores(items: items, profile: .neutral) else {
            return XCTFail("Expected scores for a non-empty sample menu")
        }
        XCTAssertEqual(combined.health,
                       MenuCheckerRepository.averageHealthScore(items: items, profile: .neutral))
        XCTAssertGreaterThan(combined.satiety, 0)
        XCTAssertLessThanOrEqual(combined.satiety, 100)
    }
}
