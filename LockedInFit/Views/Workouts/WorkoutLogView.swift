import SwiftUI
import SwiftData

/// Log sets for a workout; finishing recomputes strength scores and celebrates PRs.
struct WorkoutLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query private var strengthScores: [StrengthScore]
    @Query(filter: #Predicate<Workout> { !$0.isTemplate }) private var allWorkouts: [Workout]

    @Bindable var workout: Workout
    @State private var prMessages: [String] = []
    @State private var showPRCelebration = false
    @State private var showAddExercise = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $workout.title)
                DatePicker("Date", selection: $workout.date)
                Picker("Type", selection: Binding(get: { workout.type }, set: { workout.type = $0 })) {
                    ForEach(WorkoutType.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("Duration")
                    Spacer()
                    TextField("min", value: $workout.duration, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("min").font(.caption).foregroundStyle(.secondary)
                }
            }

            ForEach(workout.exerciseList, id: \.persistentModelID) { exercise in
                exerciseSection(exercise)
            }

            Section {
                Button { showAddExercise = true } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
            }

            Section("Wrap Up") {
                Picker("Perceived difficulty", selection: $workout.perceivedDifficulty) {
                    ForEach(0...10, id: \.self) { Text($0 == 0 ? "—" : "\($0)/10").tag($0) }
                }
                TextField("Notes", text: $workout.notes, axis: .vertical)
                Button {
                    finishWorkout()
                } label: {
                    Label(workout.completed ? "Completed ✓" : "Finish Workout", systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workout.completed)
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .sheet(isPresented: $showAddExercise) {
            ExercisePickerView { library in
                let exercise = Exercise(name: library.name, muscleGroups: library.muscles,
                                        movementPattern: library.pattern, equipment: library.equipment,
                                        order: workout.exerciseList.count)
                exercise.sets?.append(WorkoutSet(order: 0, reps: 8))
                workout.exercises?.append(exercise)
            }
        }
        .alert("Personal Record!", isPresented: $showPRCelebration) {
            Button("Locked in 🔒", role: .cancel) {}
        } message: {
            Text(prMessages.joined(separator: "\n"))
        }
    }

    @ViewBuilder
    private func exerciseSection(_ exercise: Exercise) -> some View {
        Section {
            ForEach(exercise.setList, id: \.persistentModelID) { set in
                ExerciseSetRowView(set: set, isDurationBased: exercise.movementPattern == .conditioning || set.duration > 0)
            }
            .onDelete { offsets in
                let sorted = exercise.setList
                for index in offsets {
                    exercise.sets?.removeAll { $0 === sorted[index] }
                }
            }
            Button {
                let last = exercise.setList.last
                let set = WorkoutSet(order: exercise.setList.count,
                                     reps: last?.reps ?? 8,
                                     weight: last?.weight ?? 0,
                                     duration: last?.duration ?? 0)
                exercise.sets?.append(set)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.caption)
            }
        } header: {
            HStack {
                NavigationLink(destination: ExerciseDetailView(exerciseName: exercise.name)) {
                    HStack(spacing: 4) {
                        Text(exercise.name)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.caption2)
                    }
                }
                Spacer()
                Text("rest \(exercise.restSeconds)s · RPE \(String(format: "%.0f", exercise.targetRPE))")
                    .font(.caption2)
            }
        } footer: {
            if !exercise.notes.isEmpty { Text(exercise.notes) }
        }
    }

    private func finishWorkout() {
        workout.completed = true
        detectPRs()
        let bodyweight = weights.last?.weightKg ?? 75
        StrengthScoreCalculator.recompute(workouts: allWorkouts, bodyWeightKg: bodyweight,
                                          existing: strengthScores, context: context)
    }

    /// Compare each exercise's best e1RM today vs all previous history.
    private func detectPRs() {
        prMessages = []
        for exercise in workout.exerciseList {
            guard let best = exercise.bestSet else { continue }
            let todayBest = StrengthScoreCalculator.epley1RM(weight: best.weight, reps: best.reps)
            guard todayBest > 0 else { continue }
            var previousBest = 0.0
            for other in allWorkouts where other !== workout && other.completed {
                for otherExercise in other.exerciseList where otherExercise.name == exercise.name {
                    for set in otherExercise.setList where set.completed {
                        previousBest = max(previousBest, StrengthScoreCalculator.epley1RM(weight: set.weight, reps: set.reps))
                    }
                }
            }
            if todayBest > previousBest, previousBest > 0 {
                prMessages.append("\(exercise.name): e1RM \(Int(todayBest)) kg (was \(Int(previousBest)))")
            }
        }
        if !prMessages.isEmpty { showPRCelebration = true }
    }
}

/// Pick from the built-in exercise library.
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let onPick: (LibraryExercise) -> Void

    private var filtered: [LibraryExercise] {
        search.isEmpty
            ? WorkoutGeneratorService.library
            : WorkoutGeneratorService.library.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.medium))
                        Text("\(exercise.pattern.label) · \(exercise.equipment.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search)
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
