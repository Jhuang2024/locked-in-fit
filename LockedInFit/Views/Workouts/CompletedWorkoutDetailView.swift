import SwiftUI
import SwiftData

/// Read-oriented summary of a finished workout with an obvious Edit action.
/// Editing reuses the logging form but runs in an isolated child context so the
/// user can cancel without touching the saved record. Saving persists the edit
/// in place (same identity) and rebuilds strength scores from the new data.
struct CompletedWorkoutDetailView: View {
    @Bindable var workout: Workout
    @State private var editSession: WorkoutEditSession?

    var body: some View {
        Form {
            Section {
                LabeledContent("Type", value: workout.type.label)
                LabeledContent("Date", value: Formatters.mediumDate(workout.date))
                if workout.duration > 0 {
                    LabeledContent("Duration", value: "\(Int(workout.duration)) min")
                }
                if workout.totalVolume > 0 {
                    LabeledContent("Total volume", value: "\(Int(workout.totalVolume)) kg")
                }
                if workout.perceivedDifficulty > 0 {
                    LabeledContent("Perceived difficulty", value: "\(workout.perceivedDifficulty)/10")
                }
            }

            ForEach(workout.exerciseList, id: \.persistentModelID) { exercise in
                Section {
                    ForEach(exercise.setList, id: \.persistentModelID) { set in
                        HStack {
                            Text("Set \(set.order + 1)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(setSummary(set, exercise: exercise))
                                .font(.subheadline.weight(.semibold))
                            if !set.completed {
                                Image(systemName: "circle")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    NavigationLink(destination: ExerciseDetailView(exerciseName: exercise.name)) {
                        HStack(spacing: 4) {
                            Text(exercise.name)
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.caption2)
                        }
                    }
                } footer: {
                    if !exercise.notes.isEmpty { Text(exercise.notes) }
                }
            }

            if !workout.notes.isEmpty {
                Section("Notes") {
                    Text(workout.notes)
                }
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                editSession = WorkoutEditSession(source: workout)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
        .sheet(item: $editSession) { session in
            EditWorkoutView(session: session)
        }
    }

    private func setSummary(_ set: WorkoutSet, exercise: Exercise) -> String {
        if exercise.movementPattern == .conditioning || set.duration > 0 {
            var parts = ["\(Int(set.duration))s"]
            if set.distance > 0 { parts.append("\(Int(set.distance)) m") }
            return parts.joined(separator: " · ")
        }
        return "\(Formatters.trimmed(set.weight)) kg × \(set.reps)"
    }
}

/// Holds an isolated editing copy of a workout. Backed by a non-autosaving
/// child context so cancelling simply discards the context, and saving both
/// persists the edit in place (identity preserved) and recomputes strength.
@Observable
final class WorkoutEditSession: Identifiable {
    let context: ModelContext
    let workout: Workout
    var id: PersistentIdentifier { workout.persistentModelID }

    init?(source: Workout) {
        guard let container = source.modelContext?.container else { return nil }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard let copy = context.model(for: source.persistentModelID) as? Workout else { return nil }
        self.context = context
        self.workout = copy
    }

    /// Persist the in-place edit, then rebuild strength scores from the new
    /// values so PRs, e1RMs, volume and scores never keep stale numbers.
    func save() {
        try? context.save()
        recomputeStrength()
        try? context.save()
    }

    private func recomputeStrength() {
        let workouts = (try? context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { !$0.isTemplate }))) ?? []
        let scores = (try? context.fetch(FetchDescriptor<StrengthScore>())) ?? []
        let weights = (try? context.fetch(
            FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let bodyWeight = weights.last?.weightKg ?? 75
        StrengthScoreCalculator.recompute(workouts: workouts, bodyWeightKg: bodyWeight,
                                          existing: scores, context: context)
    }
}

/// Presents the logging form over an edit session with explicit Save/Cancel.
struct EditWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutEditSession

    var body: some View {
        NavigationStack {
            WorkoutLogView(workout: session.workout, mode: .edit)
                .environment(\.modelContext, session.context)
                .navigationTitle("Edit Workout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            session.save()
                            dismiss()
                        }
                    }
                }
        }
    }
}
