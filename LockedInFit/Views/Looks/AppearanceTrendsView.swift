import SwiftUI
import SwiftData
import Charts

/// Face, body, and combined appearance score charts with correlation cards,
/// matching the WeightTrendsView chart style.
struct AppearanceTrendsView: View {
    @Query(sort: \AppearanceCheckIn.date) private var checkIns: [AppearanceCheckIn]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \BodyFatEntry.date) private var bodyFats: [BodyFatEntry]
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }, sort: \Workout.date)
    private var completedWorkouts: [Workout]
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]

    @State private var windowDays = 30

    static let allTimeWindow = Int.max

    private var cutoff: Date {
        windowDays == Self.allTimeWindow ? .distantPast : Date().daysAgo(windowDays).startOfDay
    }
    private var faceCheckIns: [AppearanceCheckIn] {
        checkIns.filter { $0.kind == .face && $0.date >= cutoff }
    }
    private var bodyCheckIns: [AppearanceCheckIn] {
        checkIns.filter { $0.kind == .body && $0.date >= cutoff }
    }
    private var latestFaceCheckIn: AppearanceCheckIn? { checkIns.last { $0.kind == .face } }
    private var latestBodyCheckIn: AppearanceCheckIn? { checkIns.last { $0.kind == .body } }
    /// Same composition-only fallback the Looks page and dashboard use, so the
    /// current score plotted here is byte-for-byte the score shown there.
    private var liveBodyScore: AppearanceScoringService.BodyScoreResult? {
        AppearanceScoringService.liveBodyScore(
            weights: weights, bodyFats: bodyFats, workouts: completedWorkouts,
            settings: settingsList.first, goal: activeGoals.first)
    }
    /// Body series: saved check-ins plus a "today" point from the shared
    /// effective-score helper whenever there is no check-in today, so the
    /// latest value here always equals the Looks page's Body score.
    private var bodyPoints: [(date: Date, score: Double)] {
        var points = bodyCheckIns.map { (date: $0.date, score: $0.totalScore) }
        if latestBodyCheckIn?.date.isToday != true,
           let current = AppearanceScoringService.effectiveBodyScore(checkIn: latestBodyCheckIn, live: liveBodyScore) {
            points.append((date: Date(), score: current))
        }
        return points
    }
    /// Combined series: for each check-in day, the recency-weighted blend of the
    /// latest face and body scores as of that date, plus a "today" point from
    /// the same liveBody-aware formula the Looks page and dashboard use.
    private var combinedPoints: [(date: Date, score: Double)] {
        let all = checkIns.filter { $0.date >= cutoff }
        var points: [(date: Date, score: Double)] = []
        for checkIn in all {
            let latestFace = checkIns.last { $0.kind == .face && $0.date <= checkIn.date }
            let latestBody = checkIns.last { $0.kind == .body && $0.date <= checkIn.date }
            if let combined = AppearanceScoringService.combinedScore(face: latestFace, body: latestBody, date: checkIn.date) {
                points.append((date: checkIn.date, score: combined))
            }
        }
        if points.last?.date.isToday != true,
           let current = AppearanceScoringService.combinedScore(
               face: latestFaceCheckIn, body: latestBodyCheckIn, liveBody: liveBodyScore) {
            points.append((date: Date(), score: current))
        }
        return points
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Window", selection: $windowDays) {
                    Text("7D").tag(7)
                    Text("30D").tag(30)
                    Text("90D").tag(90)
                    Text("All").tag(Self.allTimeWindow)
                }
                .pickerStyle(.segmented)

                scoreChart(title: "Face Score", points: faceCheckIns.map { (date: $0.date, score: $0.totalScore) },
                           color: .accentColor,
                           emptyMessage: "Face scores appear once you complete face check-ins.")
                scoreChart(title: "Body Score", points: bodyPoints,
                           color: .indigo,
                           emptyMessage: "Body scores appear once you complete body check-ins or log weight/body fat.")
                scoreChart(title: "Combined Appearance Score", points: combinedPoints,
                           color: .teal,
                           emptyMessage: "The combined score appears once you have any check-ins or body data.")

                if faceCheckIns.count >= 3 {
                    faceBreakdownChart
                }

                correlationSection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Appearance Trends")
    }

    // MARK: - Charts

    @ViewBuilder
    private func scoreChart(title: String, points: [(date: Date, score: Double)], color: Color, emptyMessage: String) -> some View {
        if points.isEmpty {
            DashboardCard(title: title, systemImage: "chart.xyaxis.line") {
                EmptyStateView(systemImage: "chart.xyaxis.line", title: "No data in this window", message: emptyMessage)
            }
        } else {
            ChartCard(title: title, subtitle: "0–100 · higher confidence with consistent photos") {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.date), y: .value("Score", point.score))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", point.date), y: .value("Score", point.score))
                            .foregroundStyle(color.opacity(0.5))
                            .symbolSize(24)
                    }
                }
                .id("\(title)-\(windowDays)")
                .chartYScale(domain: 0.0...100.0)
            }
        }
    }

    private var faceBreakdownChart: some View {
        ChartCard(title: "Face Score Breakdown", subtitle: "Component points over time") {
            Chart {
                ForEach(Array(faceCheckIns.enumerated()), id: \.offset) { _, checkIn in
                    LineMark(x: .value("Date", checkIn.date), y: .value("Points", checkIn.skinScore),
                             series: .value("Component", "Skin"))
                        .foregroundStyle(by: .value("Component", "Skin"))
                    LineMark(x: .value("Date", checkIn.date), y: .value("Points", checkIn.groomingScore),
                             series: .value("Component", "Grooming"))
                        .foregroundStyle(by: .value("Component", "Grooming"))
                    LineMark(x: .value("Date", checkIn.date), y: .value("Points", checkIn.puffinessScore),
                             series: .value("Component", "Puffiness"))
                        .foregroundStyle(by: .value("Component", "Puffiness"))
                }
            }
            .id("breakdown-\(windowDays)")
            .chartYScale(domain: 0.0...30.0)
        }
    }

    // MARK: - Correlations

    @ViewBuilder
    private var correlationSection: some View {
        let bodyAll = checkIns.filter { $0.kind == .body }
        let weightPairs = pairedValues(checkIns: bodyAll, values: weights.map { ($0.date, $0.weightKg) })
        let fatPairs = pairedValues(checkIns: bodyAll, values: bodyFats.map { ($0.date, $0.bodyFatPercentage) })
        let workoutPairs = workoutConsistencyPairs(checkIns: bodyAll)

        if weightPairs.count >= 5 || fatPairs.count >= 5 || workoutPairs.count >= 5 {
            SectionLabel(text: "Correlations")
                .frame(maxWidth: .infinity, alignment: .leading)
            if weightPairs.count >= 5 {
                correlationCard(title: "Body score vs weight", pairs: weightPairs,
                                positiveText: "Body score has risen with weight; consistent with muscle gain.",
                                negativeText: "Body score has risen as weight dropped; consistent with a productive cut.")
            }
            if fatPairs.count >= 5 {
                correlationCard(title: "Body score vs body fat", pairs: fatPairs,
                                positiveText: "Score and body fat are moving together; worth a look at training volume.",
                                negativeText: "Score improves as body fat falls, as expected.")
            }
            if workoutPairs.count >= 5 {
                correlationCard(title: "Body score vs workout consistency", pairs: workoutPairs,
                                positiveText: "More training weeks line up with better body scores.",
                                negativeText: "Training volume and body score are moving oppositely; recovery might be the limiter.")
            }
        } else if !bodyAll.isEmpty {
            DashboardCard(title: "Correlations", systemImage: "point.3.connected.trianglepath.dotted") {
                EmptyStateView(systemImage: "point.3.connected.trianglepath.dotted",
                               title: "Not enough paired data yet",
                               message: "Correlations unlock at 5+ body check-ins with matching weight, body fat, or training data.")
            }
        }
    }

    private func correlationCard(title: String, pairs: [(Double, Double)], positiveText: String, negativeText: String) -> some View {
        let r = pearson(pairs)
        return DashboardCard(title: title, systemImage: "point.3.connected.trianglepath.dotted") {
            HStack {
                StatChip(label: "Correlation", value: String(format: "%+.2f", r),
                         color: abs(r) < 0.25 ? .primary : (r > 0 ? .green : .orange))
                StatChip(label: "Strength", value: abs(r) >= 0.6 ? "Strong" : abs(r) >= 0.3 ? "Moderate" : "Weak")
                StatChip(label: "Pairs", value: "\(pairs.count)")
            }
            if abs(r) >= 0.3 {
                Text(r > 0 ? positiveText : negativeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No meaningful relationship in this data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Pair each body check-in score with the nearest value within 3 days.
    private func pairedValues(checkIns: [AppearanceCheckIn], values: [(Date, Double)]) -> [(Double, Double)] {
        checkIns.compactMap { checkIn in
            let nearest = values.min { abs($0.0.timeIntervalSince(checkIn.date)) < abs($1.0.timeIntervalSince(checkIn.date)) }
            guard let nearest, abs(nearest.0.timeIntervalSince(checkIn.date)) <= 3 * 86400 else { return nil }
            return (checkIn.totalScore, nearest.1)
        }
    }

    /// Pair each body check-in with workouts completed in the prior 14 days.
    private func workoutConsistencyPairs(checkIns: [AppearanceCheckIn]) -> [(Double, Double)] {
        checkIns.map { checkIn in
            let count = completedWorkouts.filter {
                $0.date <= checkIn.date && $0.date > checkIn.date.daysAgo(14)
            }.count
            return (checkIn.totalScore, Double(count))
        }
    }

    private func pearson(_ pairs: [(Double, Double)]) -> Double {
        let n = Double(pairs.count)
        guard n > 1 else { return 0 }
        let sumX = pairs.reduce(0) { $0 + $1.0 }
        let sumY = pairs.reduce(0) { $0 + $1.1 }
        let sumXY = pairs.reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = pairs.reduce(0) { $0 + $1.0 * $1.0 }
        let sumY2 = pairs.reduce(0) { $0 + $1.1 * $1.1 }
        let numerator = n * sumXY - sumX * sumY
        let denominator = ((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY)).squareRoot()
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}
