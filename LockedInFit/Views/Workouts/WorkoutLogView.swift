import SwiftUI
import SwiftData

/// Log sets for a workout; finishing recomputes strength scores and celebrates PRs.
struct WorkoutLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query private var strengthScores: [StrengthScore]
    @Query(filter: #Predicate<Workout> { !$0.isTemplate }) private var allWorkouts: [Workout]
    @Query private var settingsList: [UserSettings]

    @Bindable var workout: Workout
    /// `.log` drives a live logging session (with a Finish button); `.edit`
    /// reuses the same form to amend an already-completed workout, with saving
    /// handled by the presenting editor instead.
    var mode: Mode = .log
    @State private var prMessages: [String] = []
    @State private var showPRCelebration = false
    @State private var showAddExercise = false
    @State private var workoutDescription = ""
    @State private var estimating = false
    @State private var estimateError: String?
    @State private var lastEstimate: WorkoutEstimate?

    private var settings: UserSettings? { settingsList.first }

    enum Mode { case log, edit }

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
                ExerciseSectionView(exercise: exercise)
            }

            Section {
                Button { showAddExercise = true } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
            }

            Section("Wrap Up") {
                Picker("Perceived difficulty", selection: $workout.perceivedDifficulty) {
                    ForEach(0...10, id: \.self) { Text($0 == 0 ? "Not rated" : "\($0)/10").tag($0) }
                }
                TextField("Notes", text: $workout.notes, axis: .vertical)
                if mode == .log {
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

            Section {
                HStack {
                    Text("Calories")
                    Spacer()
                    TextField("kcal", value: $workout.caloriesBurned, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("kcal").font(.caption).foregroundStyle(.secondary)
                }
                TextField("Describe the workout for a calorie estimate", text: $workoutDescription, axis: .vertical)
                    .font(.subheadline)
                Button {
                    estimateCalories()
                } label: {
                    if estimating {
                        HStack { ProgressView(); Text("Estimating…") }
                    } else {
                        Label("Estimate from Description", systemImage: "sparkles")
                    }
                }
                .disabled(estimating || workoutDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let lastEstimate {
                    Text("\(Int(lastEstimate.confidence * 100))% confidence, \(lastEstimate.intensity) intensity. \(lastEstimate.notes)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let estimateError {
                    Text(estimateError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Calories Burned")
            } footer: {
                Text("Left at 0, a finished workout gets a default estimate from its duration and type.")
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .sheet(isPresented: $showAddExercise) {
            ExercisePickerView { draft in
                addExercise(from: draft)
            }
        }
        .alert("Personal Record!", isPresented: $showPRCelebration) {
            Button("Locked in 🔒", role: .cancel) {}
        } message: {
            Text(prMessages.joined(separator: "\n"))
        }
    }

    /// One entry point for both library picks and described custom exercises.
    private func addExercise(from draft: ExerciseDraft) {
        let exercise = Exercise(name: draft.name,
                                muscleGroups: draft.muscleGroups,
                                movementPattern: draft.movementPattern,
                                equipment: draft.equipment,
                                order: workout.exerciseList.count,
                                notes: draft.notes)
        for index in 0..<max(1, draft.setCount) {
            exercise.sets?.append(WorkoutSet(order: index, reps: draft.reps, weight: draft.weightKg))
        }
        workout.exercises?.append(exercise)
    }

    private func finishWorkout() {
        workout.completed = true
        if workout.caloriesBurned <= 0 {
            workout.caloriesBurned = ActivityAdjustmentCalculator.estimatedWorkoutCalories(workout)
        }
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

    private func estimateCalories() {
        let text = workoutDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        estimating = true
        estimateError = nil
        Task {
            defer { estimating = false }
            do {
                let service = AIServiceFactory.makeWorkout(settings: settings)
                let analysisContext = WorkoutAnalysisContext(workoutType: workout.type, durationMinutes: workout.duration)
                let estimate = try await service.analyzeWorkout(description: text, context: analysisContext)
                workout.caloriesBurned = estimate.estimatedCalories
                lastEstimate = estimate
            } catch {
                estimateError = error.localizedDescription
            }
        }
    }
}

/// One exercise's sets, with quick controls for how many sets and the rest
/// taken between them (rest only makes sense once there's more than one set).
private struct ExerciseSectionView: View {
    @Bindable var exercise: Exercise

    private var setsBinding: Binding<Int> {
        Binding(
            get: { exercise.setList.count },
            set: { newCount in
                let current = exercise.setList
                if newCount > current.count {
                    for i in current.count..<newCount {
                        let last = current.last
                        exercise.sets?.append(WorkoutSet(order: i,
                                                         reps: last?.reps ?? 8,
                                                         weight: last?.weight ?? 0,
                                                         duration: last?.duration ?? 0))
                    }
                } else if newCount < current.count {
                    let toDrop = Set(current.suffix(current.count - newCount).map(\.persistentModelID))
                    exercise.sets?.removeAll { toDrop.contains($0.persistentModelID) }
                }
            })
    }

    var body: some View {
        Section {
            Stepper(value: setsBinding, in: 1...20) {
                Text("Sets: \(exercise.setList.count)")
            }

            HStack {
                Text("Rest between sets")
                Spacer()
                TextField("sec", value: $exercise.restSeconds, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .disabled(exercise.setList.count <= 1)
                Text("sec").font(.caption).foregroundStyle(.secondary)
            }
            if exercise.setList.count <= 1 {
                Text("Add another set to time rest between sets.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

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
            }
        } footer: {
            if !exercise.notes.isEmpty { Text(exercise.notes) }
        }
    }
}

/// Unified exercise entry: one field that both searches the built-in library
/// and accepts a natural-language description ("incline dumbbell press,
/// 3 sets, 10 reps, 45 lb each hand"). Described entries save as custom
/// exercises for this workout without any predefined exercise existing first.
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]
    @State private var search = ""
    let onAdd: (ExerciseDraft) -> Void

    private var parsedDraft: ExerciseDraft? {
        ExerciseDescriptionParser.parse(search, units: settingsList.first?.units ?? .metric)
    }
    private var filtered: [LibraryExercise] {
        guard !search.isEmpty else { return WorkoutGeneratorService.library }
        let nameOnly = parsedDraft?.name ?? search
        return WorkoutGeneratorService.library.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(nameOnly)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let draft = parsedDraft {
                    Section {
                        Button {
                            onAdd(draft)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(draft.name, systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.medium))
                                Text("\(draft.prescriptionSummary) · \(draft.movementPattern.label) · \(draft.equipment.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(draft.matchedLibrary
                                     ? "Matched to the exercise library"
                                     : "Will be saved as a custom exercise")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("From your description")
                    }
                }

                Section {
                    if filtered.isEmpty {
                        Text("No library match. Add it from your description above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filtered) { exercise in
                        Button {
                            onAdd(.from(library: exercise))
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
                } header: {
                    Text(search.isEmpty ? "Library" : "Library matches")
                } footer: {
                    if search.isEmpty {
                        Text("Search the library, or describe an exercise with sets, reps, and weight, e.g. \"incline dumbbell press, 3 sets, 10 reps, 45 lb each hand\".")
                    }
                }
            }
            .searchable(text: $search, prompt: "Search or describe an exercise")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
