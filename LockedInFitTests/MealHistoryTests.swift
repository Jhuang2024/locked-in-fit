import XCTest
@testable import LockedInFit

/// Day-by-day food history: what the Meal History screen shows for
/// "yesterday" and every day before it.
@MainActor
final class MealHistoryTests: XCTestCase {

    /// A fixed "today" so the tests don't drift with the wall clock.
    private let today = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

    private func day(_ offset: Int) -> Date {
        Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: offset, to: today)!)
    }

    private func meal(_ dayOffset: Int, hour: Int = 12, calories: Double = 500,
                      protein: Double = 30, type: MealType = .lunch) -> MealLog {
        let date = Calendar.current.date(byAdding: .hour, value: hour, to: day(dayOffset))!
        return MealLog(date: date, mealType: type, calories: calories, protein: protein,
                       carbs: 40, fat: 15)
    }

    private func summaries(_ meals: [MealLog], goal: Goal? = nil, days: Int? = nil) -> [DayFoodSummary] {
        MealHistoryCalculator.summaries(meals: meals, goal: goal, settings: nil,
                                        days: days, today: today)
    }

    // MARK: shape

    func testNewestDayFirst() {
        let result = summaries([meal(-3), meal(-1), meal(0)])
        XCTAssertEqual(result.map(\.date), [day(0), day(-1), day(-2), day(-3)])
    }

    func testIncludesUnloggedDaysInsideTheRange() {
        // A gap has to read as "nothing logged that day", not disappear.
        let result = summaries([meal(-3), meal(0)])
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result[1].isEmpty)
        XCTAssertTrue(result[2].isEmpty)
        XCTAssertFalse(result[0].isEmpty)
        XCTAssertFalse(result[3].isEmpty)
    }

    func testNeverReachesBackBeforeTheFirstLoggedDay() {
        let result = summaries([meal(-1)], days: 90)
        XCTAssertEqual(result.map(\.date), [day(0), day(-1)])
    }

    func testWindowCountsToday() {
        let result = summaries([meal(-30)], days: 7)
        XCTAssertEqual(result.count, 7)
        XCTAssertEqual(result.last?.date, day(-6))
    }

    func testNoMealsAtAllIsEmpty() {
        XCTAssertTrue(summaries([]).isEmpty)
    }

    // MARK: per-day figures

    func testGroupsMealsIntoTheirOwnDayInTimeOrder() throws {
        let breakfast = meal(-1, hour: 8, calories: 400, type: .breakfast)
        let dinner = meal(-1, hour: 19, calories: 700, type: .dinner)
        let result = summaries([dinner, breakfast, meal(0)])
        let yesterday = try XCTUnwrap(result.first { $0.date == day(-1) })
        XCTAssertEqual(yesterday.meals.count, 2)
        XCTAssertEqual(yesterday.meals.first?.mealType, .breakfast)
        XCTAssertEqual(yesterday.nutrition.calories, 1100)
        XCTAssertEqual(yesterday.calories.eaten, 1100)
    }

    func testDayIsScoredAgainstTheGoalTarget() {
        let goal = Goal(phase: .cut, targetWeightKg: 75, calorieTarget: 2000)
        let result = summaries([meal(-1, calories: 2400)], goal: goal, days: 2)
        let yesterday = result.first { $0.date == day(-1) }
        // No activity, no oil, no portion uplift: target moves only by TEF.
        XCTAssertNotNil(yesterday)
        XCTAssertEqual(yesterday?.calories.eaten, 2400)
        XCTAssertGreaterThanOrEqual(yesterday?.calories.adjustedTarget ?? 0, 2000)
        XCTAssertLessThan(yesterday?.remaining ?? 0, 0)
    }

    // MARK: averages

    func testAveragesCountOnlyLoggedDays() {
        // Three days in range, two logged: the untracked day must not drag
        // the average down to two-thirds of what was actually eaten.
        let result = summaries([meal(-2, calories: 1000), meal(0, calories: 2000)])
        let averages = MealHistoryCalculator.averages(result)
        XCTAssertEqual(averages?.loggedDays, 2)
        XCTAssertEqual(averages?.calories, 1500)
        XCTAssertEqual(averages?.protein, 30)
    }

    func testAveragesAreNilWithNothingLogged() {
        XCTAssertNil(MealHistoryCalculator.averages([]))
    }

    // MARK: day labels

    func testDayLabels() {
        XCTAssertEqual(Formatters.dayLabel(today, relativeTo: today), "Today")
        XCTAssertEqual(Formatters.dayLabel(day(-1), relativeTo: today), "Yesterday")
        XCTAssertEqual(Formatters.dayLabel(day(1), relativeTo: today), "Tomorrow")
        // Inside the past week: the weekday name alone is unambiguous.
        XCTAssertEqual(Formatters.dayLabel(day(-3), relativeTo: today),
                       day(-3).formatted(.dateTime.weekday(.wide)))
        // Beyond it, the weekday alone would be ambiguous, so it gets a date.
        let older = Formatters.dayLabel(day(-9), relativeTo: today)
        XCTAssertNotEqual(older, day(-9).formatted(.dateTime.weekday(.wide)))
        XCTAssertFalse(older.isEmpty)
    }
}
