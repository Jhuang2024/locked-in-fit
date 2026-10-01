import XCTest
import SwiftData
@testable import LockedInFit

@MainActor
final class ReviewRegressionTests: XCTestCase {
    func testSameDayWeightsDoNotManufactureWeeklyRate() {
        let day = Calendar.current.startOfDay(for: .now)
        let entries = [BodyWeightEntry(date: day, weightKg: 70), BodyWeightEntry(date: day.addingTimeInterval(3600), weightKg: 71)]
        XCTAssertNil(WeightTrendCalculator.weeklyChangeFromEntries(entries: entries))
    }
    func testWeeklyRateUsesDistinctDailyAverages() {
        let day = Calendar.current.startOfDay(for: .now)
        let prior = Calendar.current.date(byAdding: .day, value: -7, to: day)!
        let entries = [BodyWeightEntry(date: prior, weightKg: 70), BodyWeightEntry(date: day, weightKg: 71), BodyWeightEntry(date: day.addingTimeInterval(3600), weightKg: 73)]
        XCTAssertEqual(WeightTrendCalculator.weeklyChangeFromEntries(entries: entries)!, 2, accuracy: 0.001)
    }
    func testDuplicateStepSourcesAreNotSummed() {
        let entries = [StepEntry(steps: 1000), StepEntry(steps: 1200, source: .healthKit)]
        XCTAssertEqual(Analytics.avgDailySteps(entries), 1200)
        let summary = ActivityAdjustmentCalculator.summary(steps: entries, activeEnergy: [], workouts: [], adjustment: .full)
        XCTAssertEqual(summary.baseActiveCalories, 48)
    }
    func testWHOOPUnitsAndMissingValues() {
        XCTAssertEqual(WHOOPData.kcal(kilojoules: 418.4), 100, accuracy: 0.001)
        XCTAssertNil(WHOOPData.number("score.spo2_percentage", in: ["score": ["recovery_score": 60]]))
        XCTAssertNil(WHOOPData.number("nap", in: ["nap": true]))
        XCTAssertEqual(WHOOPData.number("step_count", in: ["step_count": 0]), 0)
        XCTAssertNotNil(WHOOPData.date("2026-09-30T07:00:00.123Z"))
        XCTAssertNotNil(WHOOPData.date("2026-09-30T07:00:00Z"))
    }
    func testWHOOPPendingScoreIsNotZero() throws {
        let data = try JSONSerialization.data(withJSONObject: ["score_state": "PENDING_SCORE", "score": ["recovery_score": 0]])
        let record = WHOOPRecord(key: "recovery:1", kind: "recovery", date: .now, json: data)
        XCTAssertNil(record.recovery)
    }
    func testWHOOPUpsertAndBackupRoundTrip() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WHOOPRecord.self, configurations: config)
        let context = container.mainContext
        let dto = ExportImportService.WHOOPDTO(key: "cycle:1", kind: "cycle", date: .now, json: Data("{}".utf8), syncedAt: .now)
        try WHOOPService.upsert([dto, dto], context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WHOOPRecord>()), 1)
        var snapshot = ExportImportService.Snapshot()
        snapshot.whoopRecords = [dto]
        let restored = try JSONDecoder().decode(ExportImportService.Snapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.whoopRecords.first?.key, dto.key)
        XCTAssertEqual(restored.totalRecordCount, 1)
        let legacy = try JSONDecoder().decode(ExportImportService.Snapshot.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.whoopRecords.isEmpty)
    }
    func testMenuCheckerOilRemainsIncludedDuringBackfill() {
        let meal = MealLog(calories: 600, notes: "Logged from Menu Checker · Cafe", foodItems: [FoodItem(name: "Fried rice", grams: 200, calories: 600, cookingMethod: .stirFried)])
        XCTAssertTrue(meal.hasIncludedCookingOil)
        HiddenOilBackfill.repair([meal])
        XCTAssertEqual(meal.hiddenOilCalories, 0)
    }
    func testOneDayScheduleReallyHasOneSession() {
        var request = WorkoutScheduleGeneratorService.ScheduleRequest()
        request.daysPerWeek = 1
        request.preferredWeekdays = [2, 2]
        let schedule = WorkoutScheduleGeneratorService.generate(request: request)
        XCTAssertEqual(schedule.daysPerWeek, 1)
        XCTAssertEqual(schedule.sessions?.count, 1)
    }
    func testSickAllowanceBelongsToSelectedDay() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let settings = UserSettings()
        settings.sickDayDate = today
        let goal = Goal(phase: .maintain, targetWeightKg: 70, calorieTarget: 2000)
        let model = DashboardViewModel(settings: settings, goal: goal, meals: [], weights: [], steps: [], activeEnergy: [], workouts: [], date: yesterday)
        XCTAssertFalse(model.isSickToday)
        XCTAssertEqual(model.calories.baseTarget, 2000)
    }

    func testMalformedBackupFailsInsteadOfSilentlyDiscardingMeals() {
        XCTAssertThrowsError(try JSONDecoder().decode(ExportImportService.Snapshot.self, from: Data("{\"meals\":\"broken\"}".utf8)))
    }
    func testNumericOverflowIsRejected() {
        XCTAssertNil(NumberText.parse(String(repeating: "9", count: 400)))
    }

    func testSleepBaselineAcrossMidnightIsNotNoon() {
        XCTAssertEqual(SleepScoringService.circularMedianMinutes([1380, 1410, 30, 60]), 0, accuracy: 0.001)
        XCTAssertEqual(SleepScoringService.circularMedianMinutes([30, 60, 1380, 1410]), 0, accuracy: 0.001)
    }
    func testWorkoutCalorieOverrideSurvivesSnapshotCoding() throws {
        let dto = ExportImportService.WorkoutDTO(date: .now, title: "Walk", type: WorkoutType.conditioning.rawValue, duration: 30, notes: "", perceivedDifficulty: 5, completed: true, isTemplate: false, exercises: [], caloriesBurned: 321)
        let restored = try JSONDecoder().decode(ExportImportService.WorkoutDTO.self, from: JSONEncoder().encode(dto))
        XCTAssertEqual(restored.caloriesBurned, 321)
    }

}
