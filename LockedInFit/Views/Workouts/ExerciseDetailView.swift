import SwiftUI
import SwiftData
import Charts

/// Per-exercise history: e1RM progress chart, best set, recent sessions.
struct ExerciseDetailView: View {
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }, sort: \Workout.date)
    private var workouts: [Workout]

    let exerciseName: String

    private struct Session: Identifiable {
        let date: Date
        let best1RM: Double
        let topSet: String
        let volume: Double
        var id: Date { date }
    }

    private var sessions: [Session] {
        workouts.compactMap { workout in
            let exercises = workout.exerciseList.filter { $0.name == exerciseName }
            let sets = exercises.flatMap(\.setList).filter(\.completed)
            guard !sets.isEmpty else { return nil }
            let best = sets.max { StrengthScoreCalculator.epley1RM(weight: $0.weight, reps: $0.reps) < StrengthScoreCalculator.epley1RM(weight: $1.weight, reps: $1.reps) }!
            return Session(
                date: workout.date,
                best1RM: StrengthScoreCalculator.epley1RM(weight: best.weight, reps: best.reps),
                topSet: "\(Int(best.weight)) kg × \(best.reps)",
                volume: sets.reduce(0) { $0 + $1.weight * Double($1.reps) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if sessions.isEmpty {
                    EmptyStateView(systemImage: "dumbbell", title: "No history yet",
                                   message: "Complete a workout with \(exerciseName) to see progress here.")
                } else {
                    HStack {
                        StatChip(label: "Best e1RM", value: "\(Int(sessions.map(\.best1RM).max() ?? 0)) kg")
                        StatChip(label: "Sessions", value: "\(sessions.count)")
                        StatChip(label: "Last top set", value: sessions.last?.topSet ?? "N/A")
                    }
                    .padding(14)
                    .cardBackground()

                    ChartCard(title: "Estimated 1RM", subtitle: "Epley formula from best completed set") {
                        Chart(sessions) { session in
                            LineMark(x: .value("Date", session.date), y: .value("kg", session.best1RM))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", session.date), y: .value("kg", session.best1RM))
                                .symbolSize(28)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                    }

                    ChartCard(title: "Session Volume", subtitle: "kg × reps per session") {
                        Chart(sessions) { session in
                            BarMark(x: .value("Date", session.date), y: .value("Volume", session.volume))
                                .foregroundStyle(Color.accentColor.gradient)
                        }
                    }

                    DashboardCard(title: "Sessions", systemImage: "list.bullet") {
                        VStack(spacing: 8) {
                            ForEach(sessions.reversed()) { session in
                                HStack {
                                    Text(Formatters.mediumDate(session.date))
                                        .font(.subheadline)
                                    Spacer()
                                    Text(session.topSet)
                                        .font(.subheadline.weight(.semibold))
                                    Text("e1RM \(Int(session.best1RM))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
