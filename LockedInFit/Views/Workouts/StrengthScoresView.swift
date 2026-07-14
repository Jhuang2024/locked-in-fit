import SwiftUI
import SwiftData
import Charts

/// Gamified strength overview: overall level, per-pattern scores, badges, streaks.
struct StrengthScoresView: View {
    @Environment(\.modelContext) private var context
    @Query private var strengthScores: [StrengthScore]
    @Query(filter: #Predicate<Workout> { !$0.isTemplate }) private var workouts: [Workout]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @State private var selectedMovementLabel: String?

    private var overall: Double { StrengthScoreCalculator.overallScore(scores: strengthScores) }
    private var sortedScores: [StrengthScore] {
        strengthScores.sorted { $0.score > $1.score }
    }
    private var bestStreak: Int { strengthScores.map(\.consistencyStreak).max() ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DashboardCard(title: "Overall Strength Level", systemImage: "crown") {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: overall / 1000)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(Int(overall))")
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                Text("/1000")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 92, height: 92)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(StrengthScoreCalculator.levelName(for: overall))
                                .font(.title3.bold())
                            if bestStreak > 0 {
                                Label("\(bestStreak)-week streak", systemImage: "flame.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            Text("Score blends bodyweight-relative strength, progress, volume, and consistency.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                ChartCard(title: "Movement Balance", subtitle: "Spot weak patterns · tap or drag a bar for exact values") {
                    Chart {
                        ForEach(sortedScores, id: \.movementRaw) { score in
                            BarMark(x: .value("Score", score.score),
                                    y: .value("Movement", score.movement.label))
                                .foregroundStyle(Color.accentColor.gradient)
                        }
                        if let score = selectedStrengthScore {
                            RuleMark(y: .value("Selected movement", score.movement.label))
                                .foregroundStyle(.secondary.opacity(0.45))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .zIndex(10)
                                .annotation(
                                    position: .trailing,
                                    spacing: 4,
                                    overflowResolution: .init(
                                        x: .fit(to: .chart),
                                        y: .fit(to: .chart)
                                    )
                                ) {
                                    ChartValueCallout(title: score.movement.label, values: [
                                        ("Score", Formatters.trimmed(score.score)),
                                        ("Level", score.levelName)
                                    ])
                                }
                            PointMark(x: .value("Selected score", score.score),
                                      y: .value("Selected movement", score.movement.label))
                                .foregroundStyle(Color.accentColor)
                                .symbolSize(70)
                        }
                    }
                    .chartXScale(domain: 0...1000)
                    .chartYSelection(value: $selectedMovementLabel)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(sortedScores, id: \.movementRaw) { score in
                        StrengthScoreCard(score: score)
                    }
                }

                badges

                Button {
                    let bodyweight = weights.last?.weightKg ?? 75
                    StrengthScoreCalculator.recompute(workouts: workouts, bodyWeightKg: bodyweight,
                                                      existing: strengthScores, context: context)
                } label: {
                    Label("Recalculate Scores", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .brandScreenBackground()
        .navigationTitle("Strength Scores")
    }

    private var selectedStrengthScore: StrengthScore? {
        guard let selectedMovementLabel else { return nil }
        return sortedScores.first { $0.movement.label == selectedMovementLabel }
    }

    private var badges: some View {
        DashboardCard(title: "Badges", systemImage: "rosette") {
            let earned = sortedScores.filter { $0.score >= 450 }
            if earned.isEmpty {
                Text("Reach Intermediate (450+) in any movement to earn its badge.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(earned, id: \.movementRaw) { score in
                        HStack(spacing: 10) {
                            Image(systemName: "medal.fill")
                                .foregroundStyle(score.score >= 750 ? .yellow : (score.score >= 600 ? .purple : .blue))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(score.movement.label): \(score.levelName)")
                                    .font(.subheadline.weight(.semibold))
                                if !score.bestSetSummary.isEmpty {
                                    Text(score.bestSetSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}
