import SwiftUI
import SwiftData
import Charts

/// Calories, protein, steps, and deficit/surplus over time.
struct CalorieTrendsView: View {
    @Query(sort: \MealLog.date) private var meals: [MealLog]
    @Query(sort: \StepEntry.date) private var steps: [StepEntry]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]

    @State private var windowDays = 30

    static let allTimeWindow = Int.max

    private struct DayPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private var cutoff: Date {
        windowDays == Self.allTimeWindow ? .distantPast : Date().daysAgo(windowDays).startOfDay
    }
    private var chartEnd: Date { Date() }
    private var chartDomain: ClosedRange<Date> {
        let start: Date
        if windowDays == Self.allTimeWindow {
            let earliest = [meals.first?.date, steps.first?.date].compactMap { $0 }.min()
            start = (earliest ?? chartEnd).startOfDay
        } else {
            start = cutoff
        }
        return start...max(chartEnd, start.addingTimeInterval(86400))
    }

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
                    Text("1M").tag(30)
                    Text("2M").tag(60)
                    Text("6M").tag(180)
                    Text("1Y").tag(365)
                    Text("All").tag(Self.allTimeWindow)
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
                    .id("calories-\(windowDays)")
                    .chartXScale(domain: chartDomain)
                }

                ChartCard(title: "Deficit / Surplus", subtitle: "vs estimated maintenance (\(Int(maintenance)) kcal)") {
                    Chart(deficitPoints) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("kcal", point.value))
                            .foregroundStyle(point.value <= 0 ? Color.green.gradient : Color.red.gradient)
                    }
                    .id("deficit-\(windowDays)")
                    .chartXScale(domain: chartDomain)
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
                    .id("protein-\(windowDays)")
                    .chartXScale(domain: chartDomain)
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
                    .id("steps-\(windowDays)")
                    .chartXScale(domain: chartDomain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Calorie Trends")
    }
}
