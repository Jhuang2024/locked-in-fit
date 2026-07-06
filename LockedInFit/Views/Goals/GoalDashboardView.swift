import SwiftUI
import SwiftData
import Charts

struct GoalDashboardView: View {
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \BodyFatEntry.date) private var bodyFats: [BodyFatEntry]
    @Query(sort: \MeasurementEntry.date) private var measurements: [MeasurementEntry]
    @Query(sort: \MealLog.date) private var meals: [MealLog]
    @Query(sort: \StepEntry.date) private var steps: [StepEntry]
    @Query private var settingsList: [UserSettings]

    @State private var showEdit = false

    var body: some View {
        Group {
            if let goal = activeGoals.first, let settings = settingsList.first {
                content(goal: goal, settings: settings)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    EmptyStateView(systemImage: "target", title: "No active goal",
                                   message: "Set a goal phase to get calorie, protein, and step recommendations.")
                    Button("Set Up Goal") { showEdit = true }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding()
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Goal")
        .toolbar {
            Button(activeGoals.isEmpty ? "New" : "Edit") { showEdit = true }
        }
        .sheet(isPresented: $showEdit) {
            GoalEditView(goal: activeGoals.first)
        }
    }

    private func content(goal: Goal, settings: UserSettings) -> some View {
        let maintenance = Analytics.estimateMaintenance(settings: settings, weights: weights, meals: meals, steps: steps)
        let projection = GoalProjectionCalculator.project(goal: goal, weightEntries: weights, maintenance: maintenance, settings: settings)

        return ScrollView {
            VStack(spacing: 14) {
                DashboardCard(title: "Current Phase", systemImage: goal.phase.systemImage) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.phase.label)
                                .font(.title3.bold())
                            Text("Since \(Formatters.mediumDate(goal.startDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Adherence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(projection.adherenceScore)")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(projection.adherenceScore >= 70 ? .green : (projection.adherenceScore >= 40 ? .orange : .red))
                        }
                    }
                }

                if let warning = projection.paceWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: CardMetrics.cornerRadius, style: .continuous))
                }

                if let latestWeight = weights.last?.weightKg {
                    GoalProgressCard(
                        title: "Weight",
                        current: Formatters.kg(latestWeight),
                        target: Formatters.kg(goal.targetWeightKg),
                        progress: weightProgress(goal: goal, current: latestWeight))
                }

                if let targetBF = goal.targetBodyFatPercentage, let latestBF = bodyFats.last {
                    GoalProgressCard(
                        title: "Body Fat",
                        current: String(format: "%.1f%%", latestBF.bodyFatPercentage),
                        target: String(format: "%.1f%%", targetBF),
                        progress: bodyFatProgress(goal: goal, current: latestBF.bodyFatPercentage, target: targetBF))
                }

                DashboardCard(title: "Pace & Projection", systemImage: "calendar.badge.clock") {
                    VStack(spacing: 10) {
                        HStack {
                            StatChip(label: "Weekly trend", value: projection.weeklyRateKg.map { Formatters.kgChange($0) } ?? "—")
                            StatChip(label: "Weekly target", value: Formatters.kgChange(goal.weeklyWeightChangeTarget))
                            StatChip(label: "Projected finish", value: projection.projectedFinishDate.map { Formatters.shortDate($0) } ?? "—")
                        }
                        if let targetDate = goal.targetDate {
                            Text("Goal date: \(Formatters.mediumDate(targetDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DashboardCard(title: "Recommendations", systemImage: "lightbulb") {
                    VStack(alignment: .leading, spacing: 8) {
                        recommendationRow("flame", "Calories", "\(Int(projection.recommendedCalories)) kcal/day (maintenance \(Int(maintenance)))")
                        recommendationRow("fish", "Protein", "\(Int(projection.recommendedProtein)) g/day")
                        recommendationRow("figure.walk", "Steps", "\(projection.recommendedSteps)/day")
                    }
                }

                if !goal.measurementGoals.isEmpty {
                    measurementProgress(goal: goal)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func recommendationRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func weightProgress(goal: Goal, current: Double) -> Double {
        let total = goal.targetWeightKg - goal.startWeightKg
        guard abs(total) > 0.1 else { return 1 }
        return (current - goal.startWeightKg) / total
    }

    private func bodyFatProgress(goal: Goal, current: Double, target: Double) -> Double {
        let startBF = bodyFats.first?.bodyFatPercentage ?? current
        let total = target - startBF
        guard abs(total) > 0.1 else { return 1 }
        return (current - startBF) / total
    }

    private func measurementProgress(goal: Goal) -> some View {
        DashboardCard(title: "Measurement Goals", systemImage: "ruler") {
            VStack(spacing: 10) {
                ForEach(goal.measurementGoals.sorted(by: { $0.key < $1.key }), id: \.key) { key, target in
                    let current = latestMeasurement(for: key)
                    HStack {
                        Text(key.capitalized)
                            .font(.subheadline)
                        Spacer()
                        Text(current.map { String(format: "%.1f cm", $0) } ?? "—")
                            .font(.subheadline.weight(.semibold))
                        Text("→ \(String(format: "%.1f cm", target))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func latestMeasurement(for key: String) -> Double? {
        for entry in measurements.reversed() {
            if let field = MeasurementEntry.standardFields.first(where: { $0.key == key }) {
                if let value = entry[keyPath: field.keyPath] { return value }
            } else if let value = entry.customMeasurements[key] {
                return value
            }
        }
        return nil
    }
}
