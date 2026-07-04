import SwiftUI
import SwiftData
import Charts

struct WorkoutDashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query private var strengthScores: [StrengthScore]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]

    @State private var showGenerator = false

    private var history: [Workout] { workouts.filter { !$0.isTemplate } }
    private var templates: [Workout] { workouts.filter(\.isTemplate) }
    private var completed: [Workout] { history.filter(\.completed) }

    private var weeklyVolume: [(week: Date, volume: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: completed.filter { $0.date > Date().daysAgo(84) }) {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date.startOfDay
        }
        return grouped.map { (week: $0.key, volume: $0.value.reduce(0) { $0 + $1.totalVolume }) }
            .sorted { $0.week < $1.week }
    }

    private var overall: Double { StrengthScoreCalculator.overallScore(scores: strengthScores) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Button { showGenerator = true } label: {
                        Label("Generate", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { createBlankWorkout() } label: {
                        Label("Blank", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }

                DashboardCard(title: "Overall Strength", systemImage: "trophy") {
                    if strengthScores.isEmpty {
                        EmptyStateView(systemImage: "trophy", title: "No strength scores yet", message: "Complete workouts with logged sets to build your strength profile.")
                    } else {
                        NavigationLink(destination: StrengthScoresView()) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(Int(overall)) / 1000")
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                    Text(StrengthScoreCalculator.levelName(for: overall))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !weeklyVolume.isEmpty {
                    ChartCard(title: "Weekly Volume", subtitle: "Total kg lifted per week") {
                        Chart(weeklyVolume, id: \.week) { point in
                            BarMark(x: .value("Week", point.week, unit: .weekOfYear),
                                    y: .value("Volume", point.volume))
                                .foregroundStyle(Color.accentColor.gradient)
                        }
                    }
                }

                if !templates.isEmpty {
                    DashboardCard(title: "Templates", systemImage: "square.on.square") {
                        VStack(spacing: 10) {
                            ForEach(templates) { template in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.title).font(.subheadline.weight(.semibold))
                                        Text("\(template.exerciseList.count) exercises")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Start") { startFromTemplate(template) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                DashboardCard(title: "History", systemImage: "clock.arrow.circlepath") {
                    if history.isEmpty {
                        EmptyStateView(systemImage: "dumbbell", title: "Add your first workout", message: "Generate a plan or start a blank workout when you train.")
                    } else {
                        VStack(spacing: 10) {
                            ForEach(history.prefix(12)) { workout in
                                NavigationLink(destination: WorkoutLogView(workout: workout)) {
                                    WorkoutRowView(workout: workout)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { repeatWorkout(workout) } label: {
                                        Label("Repeat Workout", systemImage: "arrow.counterclockwise")
                                    }
                                    Button { saveAsTemplate(workout) } label: {
                                        Label("Save as Template", systemImage: "square.on.square")
                                    }
                                    Button(role: .destructive) { context.delete(workout) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
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
        .navigationTitle("Training")
        .sheet(isPresented: $showGenerator) { WorkoutGeneratorView() }
    }

    private func createBlankWorkout() {
        let workout = Workout(date: .now, title: "Workout", type: .custom)
        context.insert(workout)
    }

    private func startFromTemplate(_ template: Workout) {
        context.insert(copy(of: template, title: template.title.replacingOccurrences(of: " (Template)", with: ""), asTemplate: false))
    }

    private func repeatWorkout(_ workout: Workout) {
        context.insert(copy(of: workout, title: workout.title, asTemplate: false))
    }

    private func saveAsTemplate(_ workout: Workout) {
        context.insert(copy(of: workout, title: workout.title + " (Template)", asTemplate: true))
    }

    /// Deep copy with sets reset to planned (not completed) state.
    private func copy(of source: Workout, title: String, asTemplate: Bool) -> Workout {
        let workout = Workout(date: .now, title: title, type: source.type,
                              duration: source.duration, notes: source.notes, isTemplate: asTemplate)
        for exercise in source.exerciseList {
            let newExercise = Exercise(name: exercise.name, muscleGroups: exercise.muscleGroups,
                                       movementPattern: exercise.movementPattern, equipment: exercise.equipment,
                                       order: exercise.order, restSeconds: exercise.restSeconds,
                                       targetRPE: exercise.targetRPE, notes: exercise.notes)
            for set in exercise.setList {
                newExercise.sets?.append(WorkoutSet(order: set.order, reps: set.reps, weight: set.weight,
                                                    duration: set.duration, distance: set.distance))
            }
            workout.exercises?.append(newExercise)
        }
        return workout
    }
}
