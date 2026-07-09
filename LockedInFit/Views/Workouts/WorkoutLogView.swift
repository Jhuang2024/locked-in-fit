import SwiftUI
import SwiftData

/// Log sets for a workout; finishing recomputes strength scores and celebrates PRs.
struct WorkoutLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query private var strengthScores: [StrengthScore]
    @Query(filter: #Predicate<Workout> { !$0.isTemplate }) private var allWorkouts: [Workout]
    @Query private var settingsList: [UserSettings]
    @Query(sort: \ExercisePreset.name) private var exercisePresets: [ExercisePreset]

    @Bindable var workout: Workout
    /// `.log` drives a live logging session (with a Finish button); `.edit`
    /// reuses the same form to amend an already-completed workout, with saving
    /// handled by the presenting editor instead.
    var mode: Mode = .log
    /// True for a freshly created workout that hasn't been inserted into the
    /// model context yet (a blank workout just started) — gates the
    /// Cancel/Save toolbar so starting one and backing out never leaves a
    /// stray entry in history. Seeds `isDraft`'s @State via the custom init
    /// below so Save/Finish can flip it off after committing the workout.
    @State private var isDraft: Bool
    @State private var prMessages: [String] = []
    @State private var showPRCelebration = false
    @State private var showAddExercise = false
    @State private var showDescribeExercise = false
    @State private var estimating = false
    @State private var estimateError: String?
    @State private var lastEstimate: WorkoutEstimate?

    private var settings: UserSettings? { settingsList.first }

    enum Mode { case log, edit }

    init(workout: Workout, mode: Mode = .log, isDraft: Bool = false) {
        self.workout = workout
        self.mode = mode
        self._isDraft = State(initialValue: isDraft)
    }

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
                ExerciseSectionView(exercise: exercise) {
                    deleteExercise(exercise)
                }
            }

            Section {
                Button { showAddExercise = true } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
                Button { showDescribeExercise = true } label: {
                    Label("Describe Exercise (AI)", systemImage: "sparkles")
                }
            }

            Section("Wrap Up") {
                Picker("Perceived difficulty", selection: $workout.perceivedDifficulty) {
                    ForEach(0...10, id: \.self) { Text($0 == 0 ? "Not rated" : "\($0)/10").tag($0) }
                }
                TextField("Notes", text: $workout.notes, axis: .vertical)
                if mode == .log {
                    Button {
                        Task { await finishWorkout() }
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
                Button {
                    Task { await estimateCaloriesFromWorkout() }
                } label: {
                    if estimating {
                        HStack { ProgressView(); Text("Estimating…") }
                    } else {
                        Label("Estimate with AI", systemImage: "sparkles")
                    }
                }
                .disabled(estimating)
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
                Text("Calculated automatically from your logged exercises (via AI) when you finish the workout. Tap Estimate with AI to recalculate anytime.")
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .toolbar {
            if isDraft {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveDraft() }
                }
            }
        }
        .sheet(isPresented: $showAddExercise) {
            ExercisePickerView(presets: exercisePresets) { draft in
                addExercise(from: draft)
            }
        }
        .sheet(isPresented: $showDescribeExercise) {
            DescribeExerciseView(presets: exercisePresets) { draft in
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
                                restSeconds: draft.restSeconds,
                                targetRPE: draft.targetRPE,
                                notes: draft.notes)
        for index in 0..<max(1, draft.setCount) {
            exercise.sets?.append(WorkoutSet(order: index, reps: draft.reps, weight: draft.weightKg,
                                             duration: draft.durationSeconds, distance: draft.distanceMeters))
        }
        workout.exercises?.append(exercise)
    }

    /// Commits a blank/new workout to history and closes the sheet — the
    /// explicit, opt-in counterpart to Cancel. Never called for a workout
    /// that's already saved (isDraft false), since the toolbar buttons only
    /// show while it's still a draft.
    private func saveDraft() {
        context.insert(workout)
        ExercisePresetSyncService.addMissingPresets(for: workout.exerciseList, existingPresets: exercisePresets, context: context)
        isDraft = false
        dismiss()
    }

    /// Removes the exercise (and, via its cascade delete rule, its sets) from
    /// this workout entirely. While the workout is still an unsaved draft,
    /// the exercise was never inserted into the context in the first place
    /// (see addExercise/saveDraft), so detaching it from the array alone is
    /// enough — calling context.delete on an object the context never
    /// tracked has nothing meaningful to do.
    private func deleteExercise(_ exercise: Exercise) {
        workout.exercises?.removeAll { $0.persistentModelID == exercise.persistentModelID }
        guard !isDraft else { return }
        context.delete(exercise)
    }

    private func finishWorkout() async {
        // Finishing unambiguously means "keep this workout" — commits a
        // still-draft workout instead of requiring a separate Save tap first.
        if isDraft {
            context.insert(workout)
            isDraft = false
        }
        workout.completed = true
        if workout.caloriesBurned <= 0 {
            await estimateCaloriesFromWorkout()
        }
        detectPRs()
        let bodyweight = weights.last?.weightKg ?? 75
        // allWorkouts is a @Query result that may not have caught up yet if
        // `workout` was only just inserted above in this same call — build
        // the list explicitly so today's session is never silently excluded
        // from its own strength-score recompute.
        let workoutsForScoring = allWorkouts.contains { $0.persistentModelID == workout.persistentModelID }
            ? allWorkouts : allWorkouts + [workout]
        StrengthScoreCalculator.recompute(workouts: workoutsForScoring, bodyWeightKg: bodyweight,
                                          existing: strengthScores, context: context)
        ExercisePresetSyncService.addMissingPresets(for: workout.exerciseList, existingPresets: exercisePresets, context: context)
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

    /// Calculates calories burned from what was actually logged (exercises,
    /// sets, reps, weight, duration) via AI, instead of a user-typed
    /// description. Falls back to the local duration/type/RPE heuristic if
    /// the AI call fails (no key saved, offline, or a network error).
    private func estimateCaloriesFromWorkout() async {
        estimating = true
        estimateError = nil
        defer { estimating = false }
        do {
            let service = AIServiceFactory.makeWorkout(settings: settings)
            let description = WorkoutSummaryBuilder.describe(workout)
            let analysisContext = WorkoutAnalysisContext(workoutType: workout.type, durationMinutes: workout.duration)
            let estimate = try await service.analyzeWorkout(description: description, context: analysisContext)
            workout.caloriesBurned = estimate.estimatedCalories
            lastEstimate = estimate
        } catch {
            estimateError = error.localizedDescription
            workout.caloriesBurned = ActivityAdjustmentCalculator.estimatedWorkoutCalories(workout)
        }
    }
}

/// One exercise's sets, with quick controls for how many sets and the rest
/// taken between them (rest only makes sense once there's more than one set).
private struct ExerciseSectionView: View {
    @Bindable var exercise: Exercise
    var onDelete: () -> Void

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
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        } footer: {
            if !exercise.notes.isEmpty { Text(exercise.notes) }
        }
    }
}

/// Pick from the built-in exercise library. Describing a custom exercise
/// instead is a separate flow: see DescribeExerciseView.
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var presets: [ExercisePreset] = []
    let onAdd: (ExerciseDraft) -> Void

    private var filtered: [LibraryExercise] {
        search.isEmpty
            ? WorkoutGeneratorService.library
            : WorkoutGeneratorService.library.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
                Button {
                    onAdd(.from(library: exercise, presets: presets))
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.medium))
                        Text("\(exercise.pattern.label) · \(exercise.equipment.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let preset = ExercisePresetSyncService.matchingPreset(named: exercise.name, in: presets) {
                            Text("Saved: \(ExerciseDraft.from(preset: preset).prescriptionSummary)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

/// Describes a custom exercise in natural language and uses AI (OpenRouter,
/// or the offline parser when no key is configured) to turn it into a
/// structured ExerciseDraft, previewed here before it's added to the workout.
/// A separate feature from the library picker above, not folded into its
/// search field.
struct DescribeExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]
    @State private var description = ""
    @State private var analyzing = false
    @State private var analyzeError: String?
    @State private var draft: ExerciseDraft?
    var presets: [ExercisePreset] = []
    let onAdd: (ExerciseDraft) -> Void

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. incline dumbbell press, 3 sets, 10 reps, 45 lb each hand",
                             text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    Button {
                        analyze()
                    } label: {
                        if analyzing {
                            HStack { ProgressView(); Text("Analyzing…") }
                        } else {
                            Label("Analyze", systemImage: "sparkles")
                        }
                    }
                    .disabled(analyzing || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Describe the Exercise")
                } footer: {
                    Text("Include the name, sets, reps, and weight for the best result. AI parses this into a full entry, matching the library when it can.")
                }

                if let analyzeError {
                    Section {
                        Text(analyzeError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let draft {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.name)
                                .font(.subheadline.weight(.semibold))
                            Text("\(draft.prescriptionSummary) · \(draft.movementPattern.label) · \(draft.equipment.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(draft.matchedPreset
                                 ? "Matched to your saved preset"
                                 : draft.matchedLibrary
                                 ? "Matched to the exercise library"
                                 : "Will be saved as a custom exercise")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            onAdd(draft)
                            dismiss()
                        } label: {
                            Label("Add to Workout", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } header: {
                        Text("Result")
                    }
                }
            }
            .navigationTitle("Describe Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private func analyze() {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        analyzing = true
        analyzeError = nil
        draft = nil
        Task {
            defer { analyzing = false }
            do {
                let service = AIServiceFactory.makeExerciseAnalyzer(settings: settings)
                let analysisContext = ExerciseAnalysisContext(units: settings?.units ?? .metric)
                let estimate = try await service.analyzeExercise(description: text, context: analysisContext)
                draft = .from(estimate: estimate, presets: presets)
            } catch {
                analyzeError = error.localizedDescription
            }
        }
    }
}
