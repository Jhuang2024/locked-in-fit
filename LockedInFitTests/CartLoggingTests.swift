import XCTest
import SwiftData
@testable import LockedInFit

/// Cart totals/edits and meal logging, including duplicate-log prevention,
/// mixed-restaurant carts, and post-log editing. Uses an in-memory store.
@MainActor
final class CartLoggingTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CartLine.self, MealLog.self, FoodItem.self, FoodPreset.self,
                                           configurations: config)
        return ModelContext(container)
    }

    private func resolvedItem(_ restaurantID: String, index: Int = 0) -> (ResolvedMenuItem, String) {
        let r = SampleMenuData.restaurants.first { $0.id == restaurantID }!
        let items = SampleMenuData.menu(for: r)
        return (MenuItemResolver.resolve(item: items[index]), r.name)
    }

    private func fetchLines(_ ctx: ModelContext) throws -> [CartLine] {
        try ctx.fetch(FetchDescriptor<CartLine>(sortBy: [SortDescriptor(\.addedAt)]))
    }
    private func fetchMeals(_ ctx: ModelContext) throws -> [MealLog] {
        try ctx.fetch(FetchDescriptor<MealLog>())
    }

    // MARK: Cart totals

    func testCartTotalsSumLines() throws {
        let ctx = try makeContext()
        let (a, nameA) = resolvedItem("sample:greenfuel", index: 0)
        let (b, nameB) = resolvedItem("sample:greenfuel", index: 1)
        CartManager.add(a, restaurantName: nameA, context: ctx)
        CartManager.add(b, restaurantName: nameB, context: ctx)

        let lines = try fetchLines(ctx)
        let summary = CartManager.summary(for: lines)
        XCTAssertEqual(summary.lineCount, 2)
        XCTAssertEqual(summary.nutrition.calories, a.perUnit.calories + b.perUnit.calories, accuracy: 0.5)
        XCTAssertEqual(summary.nutrition.protein, a.perUnit.protein + b.perUnit.protein, accuracy: 0.5)
    }

    func testQuantityChangeScalesLine() throws {
        let ctx = try makeContext()
        let (a, nameA) = resolvedItem("sample:greenfuel", index: 0)
        CartManager.add(a, restaurantName: nameA, context: ctx)
        let line = try fetchLines(ctx)[0]
        CartManager.setQuantity(line, to: 3, context: ctx)
        XCTAssertEqual(line.lineNutrition.calories, a.perUnit.calories * 3, accuracy: 0.5)
        XCTAssertEqual(CartManager.summary(for: [line]).itemCount, 3)
    }

    // MARK: Portion percentage

    func testPortionPercentageScalesLoggedMeal() throws {
        let ctx = try makeContext()
        let (a, nameA) = resolvedItem("sample:greenfuel", index: 0)
        CartManager.add(a, restaurantName: nameA, context: ctx)
        let lines = try fetchLines(ctx)
        let full = CartManager.summary(for: lines).nutrition.calories

        MealCartLogger.resetDuplicateGuard()
        let opts = MealCartLogger.Options(mealType: .lunch, date: Date(timeIntervalSince1970: 1_000_000),
                                          ateFullAmount: false, portionPercent: 50)
        let result = MealCartLogger.log(lines: lines, options: opts, settings: nil, context: ctx)
        XCTAssertEqual(result, .logged)
        let meal = try fetchMeals(ctx).first!
        XCTAssertEqual(meal.calories, full * 0.5, accuracy: 1.0, "Logging 50% should halve the calories")
    }

    // MARK: Duplicate-log prevention

    func testDuplicateLogPrevented() throws {
        let ctx = try makeContext()
        let (a, nameA) = resolvedItem("sample:greenfuel", index: 0)
        CartManager.add(a, restaurantName: nameA, context: ctx)
        let lines = try fetchLines(ctx)

        MealCartLogger.resetDuplicateGuard()
        let fixed = Date(timeIntervalSince1970: 2_000_000)
        let opts = MealCartLogger.Options(mealType: .dinner, date: fixed)
        let first = MealCartLogger.log(lines: lines, options: opts, settings: nil, context: ctx, now: fixed)
        let second = MealCartLogger.log(lines: lines, options: opts, settings: nil, context: ctx,
                                        now: fixed.addingTimeInterval(1))
        XCTAssertEqual(first, .logged)
        XCTAssertEqual(second, .duplicateIgnored)
        XCTAssertEqual(try fetchMeals(ctx).count, 1, "A rapid double tap must create only one meal")
    }

    // MARK: Mixed-restaurant cart

    func testLoggingMixedRestaurantCart() throws {
        let ctx = try makeContext()
        let (a, nameA) = resolvedItem("sample:greenfuel", index: 0)
        let (b, nameB) = resolvedItem("sample:brooklynburger", index: 0)
        CartManager.add(a, restaurantName: nameA, context: ctx)
        CartManager.add(b, restaurantName: nameB, context: ctx)
        let lines = try fetchLines(ctx)
        let expected = CartManager.summary(for: lines).nutrition.calories

        MealCartLogger.resetDuplicateGuard()
        let result = MealCartLogger.log(lines: lines,
                                        options: MealCartLogger.Options(mealType: .dinner, date: Date(timeIntervalSince1970: 3_000_000)),
                                        settings: nil, context: ctx)
        XCTAssertEqual(result, .logged)
        let meal = try fetchMeals(ctx).first!
        XCTAssertEqual(meal.calories, expected, accuracy: 1.0)
        XCTAssertEqual(meal.items.count, 2, "One food item per cart line")
        XCTAssertTrue(meal.notes.contains(nameA) && meal.notes.contains(nameB),
                      "Both restaurants should be attributed in the notes")
        XCTAssertEqual(meal.analysisState, .completed)
    }

    // MARK: Editing a meal after it has been logged

    func testMealEditableAfterLogging() throws {
        let ctx = try makeContext()
        let (a, nameA) = resolvedItem("sample:greenfuel", index: 0)
        CartManager.add(a, restaurantName: nameA, context: ctx)
        let lines = try fetchLines(ctx)
        MealCartLogger.resetDuplicateGuard()
        _ = MealCartLogger.log(lines: lines,
                               options: MealCartLogger.Options(mealType: .lunch, date: Date(timeIntervalSince1970: 4_000_000)),
                               settings: nil, context: ctx)

        let meal = try fetchMeals(ctx).first!
        meal.calories = 1234
        meal.mealType = .dinner
        meal.protein = 99
        try ctx.save()

        let reloaded = try fetchMeals(ctx).first!
        XCTAssertEqual(reloaded.calories, 1234)
        XCTAssertEqual(reloaded.mealType, .dinner)
        XCTAssertEqual(reloaded.protein, 99)
    }

    // MARK: Clearing

    func testClearCartAfterLogging() throws {
        let ctx = try makeContext()
        let (a, nameA) = resolvedItem("sample:greenfuel", index: 0)
        CartManager.add(a, restaurantName: nameA, context: ctx)
        let lines = try fetchLines(ctx)
        MealCartLogger.resetDuplicateGuard()
        _ = MealCartLogger.log(lines: lines,
                               options: MealCartLogger.Options(mealType: .lunch, date: Date(timeIntervalSince1970: 5_000_000)),
                               settings: nil, context: ctx)
        MealCartLogger.clearCart(lines, context: ctx)
        XCTAssertEqual(try fetchLines(ctx).count, 0, "Cart should be empty once logged and cleared")
    }
}
