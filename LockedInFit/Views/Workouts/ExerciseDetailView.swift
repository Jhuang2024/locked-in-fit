import SwiftUI
import SwiftData
import Charts

/// Per-exercise history: e1RM progress chart, best set, recent sessions.
struct ExerciseDetailView: View {
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }, sort: \Workout.date)
    private var workouts: [Workout]

    let exerciseName: String
    @State private var selectedOneRMDate: Date?
    @State private var selectedVolumeDate: Date?

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

                    ChartCard(title: "Estimated 1RM", subtitle: "Epley formula from best completed set · tap or drag for exact values") {
                        Chart {
                            ForEach(sessions) { session in
                                LineMark(x: .value("Date", session.date), y: .value("kg", session.best1RM))
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("Date", session.date), y: .value("kg", session.best1RM))
                                    .symbolSize(28)
                            }
                            if let session = nearestSession(to: selectedOneRMDate) {
                                RuleMark(x: .value("Selected date", session.date))
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
                                        ChartPointCallout(date: session.date, values: [
                                            ("Estimated 1RM", "\(Formatters.trimmed(session.best1RM)) kg"),
                                            ("Top set", session.topSet)
                                        ])
                                    }
                                PointMark(x: .value("Selected date", session.date),
                                          y: .value("Selected 1RM", session.best1RM))
                                    .foregroundStyle(Color.accentColor)
                                    .symbolSize(70)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXSelection(value: $selectedOneRMDate)
                    }

                    ChartCard(title: "Session Volume", subtitle: "kg × reps per session · tap or drag for the exact value") {
                        Chart {
                            ForEach(sessions) { session in
                                BarMark(x: .value("Date", session.date), y: .value("Volume", session.volume))
                                    .foregroundStyle(Color.accentColor.gradient)
                            }
                            if let session = nearestSession(to: selectedVolumeDate) {
                                RuleMark(x: .value("Selected date", session.date))
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
                                        ChartPointCallout(date: session.date, values: [
                                            ("Volume", "\(Int(session.volume.rounded())) kg × reps")
                                        ])
                                    }
                                PointMark(x: .value("Selected date", session.date),
                                          y: .value("Selected volume", session.volume))
                                    .foregroundStyle(Color.accentColor)
                                    .symbolSize(70)
                            }
                        }
                        .chartXSelection(value: $selectedVolumeDate)
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
        .brandScreenBackground()
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func nearestSession(to date: Date?) -> Session? {
        guard let date else { return nil }
        return sessions.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}
