import XCTest
import SwiftData
@testable import LockedInFit

/// Food rating rules: the menu-item rating key, upsert/clear behavior for
/// MenuItemRatingRecord, and the meal-rating → preset-rating sync. Uses an
/// in-memory store.
@MainActor
final class FoodRatingTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MealLog.self, FoodItem.self, FoodPreset.self,
                                           MenuItemRatingRecord.self,
                                           configurations: config)
        return ModelContext(container)
    }

    private func sampleItem(index: Int = 0) -> (MenuItem, String) {
        let r = SampleMenuData.restaurants[0]
        return (SampleMenuData.menu(for: r)[index], r.name)
    }

    private func fetchRatings(_ ctx: ModelContext) throws -> [MenuItemRatingRecord] {
        try ctx.fetch(FetchDescriptor<MenuItemRatingRecord>())
    }

    // MARK: Key stability

    func testMenuItemKeyNormalizesName() {
        // Same dish with formatting noise must produce the same key, since
        // menu refreshes regenerate item ids and can reword capitalization.
        let a = FoodRatingService.menuItemKey(restaurantID: "r1", itemName: "Pad Thai")
        let b = FoodRatingService.menuItemKey(restaurantID: "r1", itemName: "  pad   thai. ")
        XCTAssertEqual(a, b)
        // Different restaurant → different key even for the same dish name.
        XCTAssertNotEqual(a, FoodRatingService.menuItemKey(restaurantID: "r2", itemName: "Pad Thai"))
    }

    func testRatingSurvivesItemIDChange() throws {
        let ctx = try makeContext()
        let (item, restaurantName) = sampleItem()
        FoodRatingService.setRating(4, for: item, restaurantName: restaurantName,
                                    records: [], context: ctx)

        // Simulate a menu refresh that reassigns the provider id.
        var refetched = item
        refetched.id = "totally-different-id"
        let records = try fetchRatings(ctx)
        XCTAssertEqual(FoodRatingService.rating(for: refetched, in: records), 4)
    }

    // MARK: Upsert / clear

    func testSetRatingUpsertsSingleRecord() throws {
        let ctx = try makeContext()
        let (item, restaurantName) = sampleItem()
        FoodRatingService.setRating(3, for: item, restaurantName: restaurantName,
                                    records: [], context: ctx)
        FoodRatingService.setRating(5, for: item, restaurantName: restaurantName,
                                    records: try fetchRatings(ctx), context: ctx)

        let records = try fetchRatings(ctx)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].rating, 5)
    }

    func testClearingRatingDeletesRecord() throws {
        let ctx = try makeContext()
        let (item, restaurantName) = sampleItem()
        FoodRatingService.setRating(2, for: item, restaurantName: restaurantName,
                                    records: [], context: ctx)
        FoodRatingService.setRating(0, for: item, restaurantName: restaurantName,
                                    records: try fetchRatings(ctx), context: ctx)
        XCTAssertTrue(try fetchRatings(ctx).isEmpty)
    }

    func testRatingIsClampedToScale() throws {
        let ctx = try makeContext()
        let (item, restaurantName) = sampleItem()
        FoodRatingService.setRating(99, for: item, restaurantName: restaurantName,
                                    records: [], context: ctx)
        XCTAssertEqual(try fetchRatings(ctx)[0].rating, FoodRatingService.maxRating)
    }

    // MARK: Meal → preset sync

    func testMealRatingFlowsToMatchingPresets() throws {
        let preset = FoodPreset(name: "White Rice", serving: "180 g",
                                calories: 230, protein: 4, carbs: 50, fat: 1)
        let other = FoodPreset(name: "Chicken Thigh", serving: "120 g",
                               calories: 210, protein: 25, carbs: 0, fat: 12)
        let meal = MealLog(foodItems: [FoodItem(name: " white  rice.", calories: 230)])
        meal.rating = 5

        FoodRatingService.syncPresetRatings(from: meal, presets: [preset, other])
        XCTAssertEqual(preset.rating, 5)
        XCTAssertEqual(other.rating, 0, "Foods not in the meal must keep their own rating")
    }

    func testClearingMealRatingLeavesPresetsAlone() throws {
        let preset = FoodPreset(name: "White Rice", serving: "180 g",
                                calories: 230, protein: 4, carbs: 50, fat: 1)
        preset.rating = 4
        let meal = MealLog(foodItems: [FoodItem(name: "white rice", calories: 230)])
        meal.rating = 0

        FoodRatingService.syncPresetRatings(from: meal, presets: [preset])
        XCTAssertEqual(preset.rating, 4, "A preset may have earned its stars from other meals")
    }
}
