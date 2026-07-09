import SwiftUI
import SwiftData

/// Manage saved exercise presets: view, edit, or delete what's built up
/// automatically from logged workouts (see ExercisePresetSyncService), or
/// add one by hand. Analogous to FoodPresetsView for meals.
struct ExercisePresetsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExercisePreset.name) private var presets: [ExercisePreset]
    @State private var search = ""
    @State private var editing: ExercisePreset?
    @State private var showNew = false

    private var grouped: [(pattern: MovementPattern, items: [ExercisePreset])] {
        let filtered = search.isEmpty ? presets : presets.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return Dictionary(grouping: filtered, by: \.movementPattern)
            .map { (pattern: $0.key, items: $0.value) }
            .sorted { $0.pattern.label < $1.pattern.label }
    }

    var body: some View {
        List {
            if presets.isEmpty {
                EmptyStateView(systemImage: "dumbbell",
                              title: "No exercise presets yet",
                              message: "Presets are created automatically as you log exercises, or add one here.")
            }
            ForEach(grouped, id: \.pattern) { group in
                Section(group.pattern.label) {
                    ForEach(group.items) { preset in
                        Button { editing = preset } label: {
                            ExercisePresetRowView(preset: preset)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(group.items[index]) }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Exercise Presets")
        .toolbar {
            Button { showNew = true } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editing) { preset in
            ExercisePresetEditorView(preset: preset)
        }
        .sheet(isPresented: $showNew) {
            ExercisePresetEditorView(preset: nil)
        }
    }
}

struct ExercisePresetRowView: View {
    let preset: ExercisePreset

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(preset.name)
                .font(.subheadline.weight(.medium))
            Text("\(ExerciseDraft.from(preset: preset).prescriptionSummary) · \(preset.equipment.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !preset.muscleGroups.isEmpty {
                Text(preset.muscleGroups.map(\.label).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct ExercisePresetEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let preset: ExercisePreset?

    @State private var name = ""
    @State private var movementPattern: MovementPattern = .horizontalPush
    @State private var equipment: Equipment = .barbell
    @State private var muscleGroups: Set<MuscleGroup> = []
    @State private var restSeconds = 90
    @State private var targetRPE: Double = 8
    @State private var setCount = 3
    @State private var reps = 8
    @State private var weightKg: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var distanceMeters: Double = 0
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                    Picker("Movement pattern", selection: $movementPattern) {
                        ForEach(MovementPattern.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Muscle groups") {
                    ForEach(MuscleGroup.allCases) { muscle in
                        Toggle(muscle.label, isOn: Binding(
                            get: { muscleGroups.contains(muscle) },
                            set: { on in if on { muscleGroups.insert(muscle) } else { muscleGroups.remove(muscle) } }))
                    }
                }
                Section("Typical prescription") {
                    Stepper("Sets: \(setCount)", value: $setCount, in: 1...20)
                    Stepper("Reps: \(reps)", value: $reps, in: 1...100)
                    field("Weight", value: $weightKg, unit: "kg")
                    if movementPattern == .conditioning {
                        field("Duration", value: $durationSeconds, unit: "sec")
                        field("Distance", value: $distanceMeters, unit: "m")
                    }
                    Stepper("Rest: \(restSeconds)s", value: $restSeconds, in: 0...600, step: 15)
                    HStack {
                        Text("Target RPE")
                        Spacer()
                        TextField("0", value: $targetRPE, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if preset != nil {
                    Section {
                        Button("Delete Preset", role: .destructive) {
                            if let preset { context.delete(preset) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(preset == nil ? "New Preset" : "Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { load() }
        }
    }

    private func field(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }

    private func load() {
        guard let preset else { return }
        name = preset.name
        movementPattern = preset.movementPattern
        equipment = preset.equipment
        muscleGroups = Set(preset.muscleGroups)
        restSeconds = preset.restSeconds
        targetRPE = preset.targetRPE
        setCount = preset.setCount
        reps = preset.reps
        weightKg = preset.weightKg
        durationSeconds = preset.durationSeconds
        distanceMeters = preset.distanceMeters
        notes = preset.notes
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preset {
            preset.name = trimmedName
            preset.movementPattern = movementPattern
            preset.equipment = equipment
            preset.muscleGroups = Array(muscleGroups)
            preset.restSeconds = restSeconds
            preset.targetRPE = targetRPE
            preset.setCount = setCount
            preset.reps = reps
            preset.weightKg = weightKg
            preset.durationSeconds = durationSeconds
            preset.distanceMeters = distanceMeters
            preset.notes = notes
        } else {
            context.insert(ExercisePreset(
                name: trimmedName,
                muscleGroups: Array(muscleGroups),
                movementPattern: movementPattern,
                equipment: equipment,
                restSeconds: restSeconds,
                targetRPE: targetRPE,
                notes: notes,
                setCount: setCount,
                reps: reps,
                weightKg: weightKg,
                durationSeconds: durationSeconds,
                distanceMeters: distanceMeters))
        }
        dismiss()
    }
}
