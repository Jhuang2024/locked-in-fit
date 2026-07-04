import SwiftUI
import SwiftData

struct WorkoutGeneratorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]

    @State private var type: WorkoutType = .fullBody
    @State private var equipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable, .bodyweight]
    @State private var targetMuscles: Set<MuscleGroup> = []
    @State private var timeAvailable = 60
    @State private var fatigue = 2
    @State private var daysPerWeek = 4
    @State private var preview: Workout?

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    previewSection(preview)
                }

                Section("Style") {
                    Picker("Workout type", selection: $type) {
                        ForEach(WorkoutType.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("Time: \(timeAvailable) min", value: $timeAvailable, in: 20...120, step: 5)
                    Stepper("Training days/week: \(daysPerWeek)", value: $daysPerWeek, in: 1...7)
                    Picker("Soreness / fatigue", selection: $fatigue) {
                        Text("Fresh").tag(0)
                        Text("Normal").tag(2)
                        Text("Somewhat tired").tag(5)
                        Text("Wrecked").tag(8)
                    }
                }

                Section("Equipment available") {
                    ForEach(Equipment.allCases) { item in
                        Toggle(item.label, isOn: Binding(
                            get: { equipment.contains(item) },
                            set: { on in if on { equipment.insert(item) } else { equipment.remove(item) } }))
                    }
                }

                Section("Focus muscles (optional)") {
                    ForEach(MuscleGroup.allCases) { muscle in
                        Toggle(muscle.label, isOn: Binding(
                            get: { targetMuscles.contains(muscle) },
                            set: { on in if on { targetMuscles.insert(muscle) } else { targetMuscles.remove(muscle) } }))
                    }
                }
            }
            .navigationTitle("Generate Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(preview == nil ? "Generate" : "Regenerate") { generate() }
                }
            }
        }
    }

    @ViewBuilder
    private func previewSection(_ workout: Workout) -> some View {
        Section {
            ForEach(workout.exerciseList, id: \.persistentModelID) { exercise in
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.semibold))
                    Text("\(exercise.setList.count) sets × \(exercise.setList.first?.reps ?? 0) reps · rest \(exercise.restSeconds)s · RPE \(String(format: "%.0f", exercise.targetRPE))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !exercise.notes.isEmpty {
                        Text(exercise.notes)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Button {
                context.insert(workout)
                dismiss()
            } label: {
                Label("Start This Workout", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } header: {
            Text("Preview: \(workout.title)")
        } footer: {
            if !workout.notes.isEmpty { Text(workout.notes) }
        }
    }

    private func generate() {
        let request = GeneratorRequest(
            phase: goals.first?.phase ?? .maintain,
            type: type,
            availableEquipment: equipment,
            targetMuscles: targetMuscles,
            timeAvailableMinutes: timeAvailable,
            fatigueLevel: fatigue,
            trainingDaysPerWeek: daysPerWeek)
        preview = WorkoutGeneratorService.generate(request: request)
    }
}
