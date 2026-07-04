import SwiftUI
import SwiftData
import Charts

/// Calories, protein, steps, and deficit/surplus over recent weeks.
struct WeeklyTrendsView: View {
    @Query(sort: \MealLog.date) private var meals: [MealLog]
    @Query(sort: \StepEntry.date) private var steps: [StepEntry]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]

    @State private var windowDays = 28

    private struct DayPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private var cutoff: Date { Date().daysAgo(windowDays).startOfDay }

    private var caloriePoints: [DayPoint] {
        Analytics.dailyCalories(meals.filter { $0.date >= cutoff })
            .map { DayPoint(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }
    private var proteinPoints: [DayPoint] {
        Analytics.dailyProtein(meals.filter { $0.date >= cutoff })
            .map { DayPoint(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }
    private var stepPoints: [DayPoint] {
        steps.filter { $0.date >= cutoff }
            .map { DayPoint(date: $0.date.startOfDay, value: Double($0.steps)) }
            .sorted { $0.date < $1.date }
    }
    private var maintenance: Double {
        guard let settings = settingsList.first else { return 2400 }
        return Analytics.estimateMaintenance(settings: settings, weights: weights, meals: meals, steps: steps)
    }
    private var deficitPoints: [DayPoint] {
        caloriePoints.map { DayPoint(date: $0.date, value: $0.value - maintenance) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Window", selection: $windowDays) {
                    Text("2W").tag(14)
                    Text("4W").tag(28)
                    Text("8W").tag(56)
                }
                .pickerStyle(.segmented)

                ChartCard(title: "Calories", subtitle: goals.first.map { "Target \(Int($0.calorieTarget)) kcal" }) {
                    Chart(caloriePoints) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("kcal", point.value))
                            .foregroundStyle(Color.accentColor.gradient)
                        if let goal = goals.first {
                            RuleMark(y: .value("Target", goal.calorieTarget))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ChartCard(title: "Deficit / Surplus", subtitle: "vs estimated maintenance (\(Int(maintenance)) kcal)") {
                    Chart(deficitPoints) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("kcal", point.value))
                            .foregroundStyle(point.value <= 0 ? Color.green.gradient : Color.red.gradient)
                    }
                }

                ChartCard(title: "Protein", subtitle: goals.first.map { "Target \(Int($0.proteinTarget)) g" }) {
                    Chart(proteinPoints) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("g", point.value))
                            .foregroundStyle(Color.red.gradient)
                        if let goal = goals.first {
                            RuleMark(y: .value("Target", goal.proteinTarget))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ChartCard(title: "Steps", subtitle: goals.first.map { "Target \($0.stepTarget)" }) {
                    Chart(stepPoints) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("steps", point.value))
                            .foregroundStyle(Color.teal.gradient)
                        if let goal = goals.first {
                            RuleMark(y: .value("Target", Double(goal.stepTarget)))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Weekly Trends")
    }
}
