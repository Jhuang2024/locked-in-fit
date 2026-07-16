import SwiftUI
import SwiftData
import Charts

/// Calories, protein, steps, and deficit/surplus over time.
struct CalorieTrendsView: View {
    @Query(sort: \MealLog.date) private var meals: [MealLog]
    @Query(sort: \StepEntry.date) private var steps: [StepEntry]
    @Query(sort: \ActiveEnergyEntry.date) private var activeEnergy: [ActiveEnergyEntry]
    @Query(sort: \Workout.date) private var workouts: [Workout]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]

    @State private var windowDays = 30
    @State private var selectedCalorieDate: Date?
    @State private var selectedDeficitDate: Date?
    @State private var selectedProteinDate: Date?
    @State private var selectedStepsDate: Date?

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

    /// Net calories: what's eaten (logged food, plus hidden oil and the
    /// portion-underestimation allowance) minus what digesting it burns (TEF)
    /// and minus that day's activity burn: the figure that actually counts
    /// against the flat target, not raw logged intake. Activity uses the same
    /// full model as the dashboard (Apple Health active energy or the
    /// step+workout estimate, whichever is larger) so the two views agree.
    private var caloriePoints: [DayPoint] {
        let eaten = Analytics.dailyCalories(meals.filter { $0.date >= cutoff })
        let tef = tefByDay
        let portion = portionUpliftByDay
        let weight = currentWeightKg
        return eaten.map { day, calories in
            let activityBurn = ActivityAdjustmentCalculator.summary(
                for: day, steps: steps, activeEnergy: activeEnergy, workouts: workouts,
                adjustment: .full, bodyWeightKg: weight
            ).adjustmentCalories
            return DayPoint(date: day, value: calories + (portion[day] ?? 0) - (tef[day] ?? 0) - activityBurn)
        }.sorted { $0.date < $1.date }
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

    /// Whether TEF should be subtracted from intake, matching the dashboard's toggle.
    private var applyTEF: Bool { settingsList.first?.applyTEF ?? true }

    private var tefByDay: [Date: Double] {
        applyTEF ? Analytics.dailyTEF(meals.filter { $0.date >= cutoff }) : [:]
    }

    /// Current bodyweight, used to weight-scale step-calorie burn the same way
    /// the dashboard's activity model does.
    private var currentWeightKg: Double {
        WeightTrendCalculator.currentTrendKg(entries: weights) ?? weights.last?.weightKg ?? 75
    }

    /// The user's portion-underestimation setting, applied to all logged food
    /// (hidden oil is estimated separately), matching the dashboard.
    private var portionUplift: Double {
        (settingsList.first?.portionEstimationAdjustment ?? .off).uplift
    }

    private var portionUpliftByDay: [Date: Double] {
        guard portionUplift > 0 else { return [:] }
        return Dictionary(grouping: meals.filter { $0.date >= cutoff }, by: { $0.date.startOfDay })
            .mapValues { entries in entries.reduce(0) { $0 + $1.calories } * portionUplift }
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

                ChartCard(title: "Calories", subtitle: goals.first.map { "Target \(Int($0.calorieTarget)) kcal · includes hidden oil\(portionUplift > 0 ? " & portions" : ""), net of TEF & activity · tap or drag for exact values" }) {
                    Chart {
                        ForEach(caloriePoints) { point in
                            BarMark(x: .value("Day", point.date, unit: .day), y: .value("kcal", point.value))
                                .foregroundStyle(Color.accentColor.gradient)
                        }
                        if let goal = goals.first {
                            RuleMark(y: .value("Target", goal.calorieTarget))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.secondary)
                        }
                        if let point = nearestDayPoint(to: selectedCalorieDate, in: caloriePoints) {
                            RuleMark(x: .value("Selected day", point.date, unit: .day))
                                .foregroundStyle(.secondary.opacity(0.45))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .zIndex(10)
                                .annotation(
                                    position: .top,
                                    spacing: 4,
                                    overflowResolution: .init(
                                        x: .fit(to: .chart),
                                        y: .fit(to: .chart)
                                    )
                                ) {
                                    ChartPointCallout(date: point.date, values: calorieCalloutValues(for: point))
                                }
                            PointMark(x: .value("Selected day", point.date, unit: .day),
                                      y: .value("Selected calories", point.value))
                                .foregroundStyle(Color.accentColor)
                                .symbolSize(70)
                        }
                    }
                    .id("calories-\(windowDays)")
                    .chartXScale(domain: chartDomain)
                    .chartXSelection(value: $selectedCalorieDate)
                }

                ChartCard(title: "Deficit / Surplus", subtitle: "net of TEF & activity, vs estimated maintenance (\(Int(maintenance)) kcal) · tap or drag for the exact value") {
                    Chart {
                        ForEach(deficitPoints) { point in
                            BarMark(x: .value("Day", point.date, unit: .day), y: .value("kcal", point.value))
                                .foregroundStyle(point.value <= 0 ? Color.green.gradient : Color.red.gradient)
                        }
                        if let point = nearestDayPoint(to: selectedDeficitDate, in: deficitPoints) {
                            RuleMark(x: .value("Selected day", point.date, unit: .day))
                                .foregroundStyle(.secondary.opacity(0.45))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .zIndex(10)
                                .annotation(
                                    position: .top,
                                    spacing: 4,
                                    overflowResolution: .init(
                                        x: .fit(to: .chart),
                                        y: .fit(to: .chart)
                                    )
                                ) {
                                    ChartPointCallout(date: point.date, values: [
                                        (point.value <= 0 ? "Deficit" : "Surplus", String(format: "%+.0f kcal", point.value)),
                                        ("Maintenance", Formatters.kcal(maintenance))
                                    ])
                                }
                            PointMark(x: .value("Selected day", point.date, unit: .day),
                                      y: .value("Selected balance", point.value))
                                .foregroundStyle(point.value <= 0 ? Color.green : Color.red)
                                .symbolSize(70)
                        }
                    }
                    .id("deficit-\(windowDays)")
                    .chartXScale(domain: chartDomain)
                    .chartXSelection(value: $selectedDeficitDate)
                }

                ChartCard(title: "Protein", subtitle: goals.first.map { "Target \(Int($0.proteinTarget)) g · tap or drag for exact values" }) {
                    Chart {
                        ForEach(proteinPoints) { point in
                            BarMark(x: .value("Day", point.date, unit: .day), y: .value("g", point.value))
                                .foregroundStyle(Color.red.gradient)
                        }
                        if let goal = goals.first {
                            RuleMark(y: .value("Target", goal.proteinTarget))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.secondary)
                        }
                        if let point = nearestDayPoint(to: selectedProteinDate, in: proteinPoints) {
                            RuleMark(x: .value("Selected day", point.date, unit: .day))
                                .foregroundStyle(.secondary.opacity(0.45))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .zIndex(10)
                                .annotation(
                                    position: .top,
                                    spacing: 4,
                                    overflowResolution: .init(
                                        x: .fit(to: .chart),
                                        y: .fit(to: .chart)
                                    )
                                ) {
                                    ChartPointCallout(date: point.date, values: proteinCalloutValues(for: point))
                                }
                            PointMark(x: .value("Selected day", point.date, unit: .day),
                                      y: .value("Selected protein", point.value))
                                .foregroundStyle(Color.red)
                                .symbolSize(70)
                        }
                    }
                    .id("protein-\(windowDays)")
                    .chartXScale(domain: chartDomain)
                    .chartXSelection(value: $selectedProteinDate)
                }

                ChartCard(title: "Steps", subtitle: goals.first.map { "Target \($0.stepTarget) · tap or drag for exact values" }) {
                    Chart {
                        ForEach(stepPoints) { point in
                            BarMark(x: .value("Day", point.date, unit: .day), y: .value("steps", point.value))
                                .foregroundStyle(Color.teal.gradient)
                        }
                        if let goal = goals.first {
                            RuleMark(y: .value("Target", Double(goal.stepTarget)))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.secondary)
                        }
                        if let point = nearestDayPoint(to: selectedStepsDate, in: stepPoints) {
                            RuleMark(x: .value("Selected day", point.date, unit: .day))
                                .foregroundStyle(.secondary.opacity(0.45))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .zIndex(10)
                                .annotation(
                                    position: .top,
                                    spacing: 4,
                                    overflowResolution: .init(
                                        x: .fit(to: .chart),
                                        y: .fit(to: .chart)
                                    )
                                ) {
                                    ChartPointCallout(date: point.date, values: stepsCalloutValues(for: point))
                                }
                            PointMark(x: .value("Selected day", point.date, unit: .day),
                                      y: .value("Selected steps", point.value))
                                .foregroundStyle(Color.teal)
                                .symbolSize(70)
                        }
                    }
                    .id("steps-\(windowDays)")
                    .chartXScale(domain: chartDomain)
                    .chartXSelection(value: $selectedStepsDate)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .brandScreenBackground()
        .navigationTitle("Calorie Trends")
    }

    private func nearestDayPoint(to date: Date?, in points: [DayPoint]) -> DayPoint? {
        guard let date else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func calorieCalloutValues(for point: DayPoint) -> [(label: String, value: String)] {
        var values: [(label: String, value: String)] = [("Net calories", Formatters.kcal(point.value))]
        if let goal = goals.first { values.append(("Target", Formatters.kcal(goal.calorieTarget))) }
        return values
    }

    private func proteinCalloutValues(for point: DayPoint) -> [(label: String, value: String)] {
        var values: [(label: String, value: String)] = [("Protein", Formatters.grams(point.value))]
        if let goal = goals.first { values.append(("Target", Formatters.grams(goal.proteinTarget))) }
        return values
    }

    private func stepsCalloutValues(for point: DayPoint) -> [(label: String, value: String)] {
        var values: [(label: String, value: String)] = [("Steps", "\(Int(point.value.rounded()))")]
        if let goal = goals.first { values.append(("Target", "\(goal.stepTarget)")) }
        return values
    }
}
