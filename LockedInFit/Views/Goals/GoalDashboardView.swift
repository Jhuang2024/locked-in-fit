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
    @Query private var suggestions: [AppearanceSuggestion]

    var body: some View {
        Group {
            if let goal = activeGoals.first, let settings = settingsList.first {
                content(goal: goal, settings: settings)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    EmptyStateView(systemImage: "target", title: "No active goal",
                                   message: "Set up a goal in Settings → Goal to get calorie, protein, and step recommendations here.")
                    Spacer()
                }
                .padding()
                .brandScreenBackground()
            }
        }
        .navigationTitle("Goal")
    }

    private func content(goal: Goal, settings: UserSettings) -> some View {
        let maintenance = Analytics.estimateMaintenance(settings: settings, weights: weights, meals: meals, steps: steps)
        let projection = GoalProjectionCalculator.project(goal: goal, weightEntries: weights)

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
                            StatChip(label: "Weekly trend", value: projection.weeklyRateKg.map { Formatters.kgChange($0) } ?? "N/A",
                                     color: paceColor(projection))
                            StatChip(label: "Weekly target", value: Formatters.kgChange(goal.weeklyWeightChangeTarget), color: .blue)
                            StatChip(label: "Projected finish", value: finishChip(projection).value, color: finishChip(projection).color)
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

                if !activeFocuses.isEmpty {
                    activeFocusesCard
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .brandScreenBackground()
    }

    /// Approved, long-term appearance suggestions read as standing goals here:
    /// the natural place a "hold this for months" suggestion lands once approved.
    private var activeFocuses: [AppearanceSuggestion] {
        suggestions.filter { $0.status == .approved && $0.durationType == .longTerm }
    }

    private var activeFocusesCard: some View {
        DashboardCard(title: "Active Focuses", systemImage: "target") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(activeFocuses, id: \.persistentModelID) { suggestion in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: suggestion.category.systemImage)
                            .foregroundStyle(.tint)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.subheadline.weight(.medium))
                            Text(suggestion.expectedImpact)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                Text("From approved face/body check-in suggestions marked long-term.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
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

    /// Green when the observed rate is tracking the target (high adherence),
    /// orange when drifting, red when off pace or moving the wrong way. Muted
    /// when there's no rate yet.
    private func paceColor(_ projection: GoalProjection) -> Color {
        guard projection.weeklyRateKg != nil else { return .secondary }
        let score = projection.adherenceScore
        return score >= 70 ? .green : (score >= 40 ? .orange : .red)
    }

    /// The projected-finish chip: a real date when we're actually heading toward
    /// a target, otherwise an honest status instead of a made-up date.
    private func finishChip(_ projection: GoalProjection) -> (value: String, color: Color) {
        if let date = projection.projectedFinishDate {
            return (Formatters.shortDate(date), .blue)
        }
        if projection.hasReachedGoal { return ("At goal", .green) }
        if projection.isMaintaining { return ("Maintaining", .blue) }
        return ("N/A", .secondary)
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
                        Text(current.map { String(format: "%.1f cm", $0) } ?? "N/A")
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
