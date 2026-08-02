import XCTest
@testable import LockedInFit

/// The dashboard shows the day's active energy twice: once raw, as the Activity
/// card's "Est. active" chip, and once as the "Exercise" chip crediting it back
/// to the calorie target. The bug these exist for: 451.6 kcal displayed as 451
/// in one chip (truncated) and +452 in the other (rounded), so the same number
/// disagreed with itself on one screen.
@MainActor
final class ActivityAdjustmentTests: XCTestCase {

    private func summary(activeEnergy: Double,
                         adjustment: ExerciseCalorieAdjustment = .full) -> ActivityAdjustmentSummary {
        ActivityAdjustmentCalculator.summary(
            steps: [],
            activeEnergy: [ActiveEnergyEntry(calories: activeEnergy)],
            workouts: [],
            adjustment: adjustment
        )
    }

    func testActiveEnergyIsRoundedNotTruncated() {
        XCTAssertEqual(summary(activeEnergy: 451.6).baseActiveCalories, 452)
        XCTAssertEqual(summary(activeEnergy: 451.4).baseActiveCalories, 451)
    }

    func testEstimatedActiveEnergyIsRoundedToo() {
        // No Apple Health reading: the steps-and-workouts estimate is the one
        // that reaches both chips, and it has to be whole as well.
        let estimated = ActivityAdjustmentCalculator.summary(
            steps: [StepEntry(steps: 13_174)],
            activeEnergy: [],
            workouts: [],
            adjustment: .full
        )
        XCTAssertEqual(estimated.baseActiveCalories, estimated.baseActiveCalories.rounded())
    }

    /// At the full multiplier the Exercise chip credits every active calorie,
    /// so the two chips must print the identical integer.
    func testExerciseChipMatchesActiveEnergyChip() {
        for energy in [451.6, 451.5, 451.4, 0.5, 2318.7] {
            let activity = summary(activeEnergy: energy)
            let calories = CalorieRemainingCalculator.summary(
                baseTarget: 1900,
                nutrition: DailyNutritionCalculator.summary(meals: []),
                activityAdjustment: activity
            )
            XCTAssertEqual(Int(activity.baseActiveCalories),
                           Int(calories.exerciseAdjustment),
                           "Active energy and Exercise chips disagree for \(energy) kcal")
        }
    }
}
