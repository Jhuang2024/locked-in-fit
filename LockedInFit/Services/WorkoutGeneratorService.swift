import Foundation

/// Static exercise library entry used by the generator.
struct LibraryExercise: Identifiable, Hashable {
    let name: String
    let pattern: MovementPattern
    let muscles: [MuscleGroup]
    let equipment: Equipment
    /// Bigger = more systemically demanding; compounds first.
    let priority: Int

    var id: String { name }
}

struct GeneratorRequest {
    var phase: GoalPhase = .maintain
    var type: WorkoutType = .fullBody
    var availableEquipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable, .bodyweight]
    var targetMuscles: Set<MuscleGroup> = []
    var timeAvailableMinutes: Int = 60
    /// 0 fresh – 10 wrecked.
    var fatigueLevel: Int = 2
    var trainingDaysPerWeek: Int = 4
}

enum WorkoutGeneratorService {

    static let library: [LibraryExercise] = [
        // Squat / lower push
        .init(name: "Back Squat", pattern: .squat, muscles: [.quads, .glutes], equipment: .barbell, priority: 10),
        .init(name: "Front Squat", pattern: .squat, muscles: [.quads, .core], equipment: .barbell, priority: 9),
        .init(name: "Goblet Squat", pattern: .squat, muscles: [.quads, .glutes], equipment: .dumbbell, priority: 7),
        .init(name: "Leg Press", pattern: .squat, muscles: [.quads, .glutes], equipment: .machine, priority: 7),
        .init(name: "Bulgarian Split Squat", pattern: .squat, muscles: [.quads, .glutes], equipment: .dumbbell, priority: 8),
        .init(name: "Walking Lunge", pattern: .squat, muscles: [.quads, .glutes], equipment: .dumbbell, priority: 6),
        .init(name: "Bodyweight Squat", pattern: .squat, muscles: [.quads], equipment: .bodyweight, priority: 3),
        // Hinge
        .init(name: "Deadlift", pattern: .hinge, muscles: [.hamstrings, .glutes, .back], equipment: .barbell, priority: 10),
        .init(name: "Romanian Deadlift", pattern: .hinge, muscles: [.hamstrings, .glutes], equipment: .barbell, priority: 9),
        .init(name: "Dumbbell RDL", pattern: .hinge, muscles: [.hamstrings, .glutes], equipment: .dumbbell, priority: 7),
        .init(name: "Hip Thrust", pattern: .hinge, muscles: [.glutes], equipment: .barbell, priority: 7),
        .init(name: "Kettlebell Swing", pattern: .hinge, muscles: [.glutes, .hamstrings], equipment: .kettlebell, priority: 6),
        .init(name: "Leg Curl", pattern: .hinge, muscles: [.hamstrings], equipment: .machine, priority: 5),
        // Horizontal push
        .init(name: "Bench Press", pattern: .horizontalPush, muscles: [.chest, .triceps, .shoulders], equipment: .barbell, priority: 10),
        .init(name: "Dumbbell Bench Press", pattern: .horizontalPush, muscles: [.chest, .triceps], equipment: .dumbbell, priority: 8),
        .init(name: "Incline Dumbbell Press", pattern: .horizontalPush, muscles: [.chest, .shoulders], equipment: .dumbbell, priority: 8),
        .init(name: "Push-Up", pattern: .horizontalPush, muscles: [.chest, .triceps], equipment: .bodyweight, priority: 5),
        .init(name: "Cable Fly", pattern: .horizontalPush, muscles: [.chest], equipment: .cable, priority: 4),
        .init(name: "Machine Chest Press", pattern: .horizontalPush, muscles: [.chest, .triceps], equipment: .machine, priority: 6),
        // Vertical push
        .init(name: "Overhead Press", pattern: .verticalPush, muscles: [.shoulders, .triceps], equipment: .barbell, priority: 9),
        .init(name: "Dumbbell Shoulder Press", pattern: .verticalPush, muscles: [.shoulders], equipment: .dumbbell, priority: 8),
        .init(name: "Lateral Raise", pattern: .verticalPush, muscles: [.shoulders], equipment: .dumbbell, priority: 4),
        .init(name: "Pike Push-Up", pattern: .verticalPush, muscles: [.shoulders, .triceps], equipment: .bodyweight, priority: 4),
        // Horizontal pull
        .init(name: "Barbell Row", pattern: .horizontalPull, muscles: [.back, .biceps], equipment: .barbell, priority: 9),
        .init(name: "Dumbbell Row", pattern: .horizontalPull, muscles: [.back, .biceps], equipment: .dumbbell, priority: 8),
        .init(name: "Seated Cable Row", pattern: .horizontalPull, muscles: [.back, .biceps], equipment: .cable, priority: 7),
        .init(name: "Chest-Supported Row", pattern: .horizontalPull, muscles: [.back], equipment: .machine, priority: 7),
        .init(name: "Inverted Row", pattern: .horizontalPull, muscles: [.back, .biceps], equipment: .bodyweight, priority: 5),
        // Vertical pull
        .init(name: "Pull-Up", pattern: .verticalPull, muscles: [.back, .biceps], equipment: .bodyweight, priority: 9),
        .init(name: "Lat Pulldown", pattern: .verticalPull, muscles: [.back, .biceps], equipment: .cable, priority: 8),
        .init(name: "Chin-Up", pattern: .verticalPull, muscles: [.back, .biceps], equipment: .bodyweight, priority: 8),
        .init(name: "Band Pulldown", pattern: .verticalPull, muscles: [.back], equipment: .band, priority: 3),
        // Core
        .init(name: "Plank", pattern: .core, muscles: [.core], equipment: .bodyweight, priority: 5),
        .init(name: "Hanging Leg Raise", pattern: .core, muscles: [.core], equipment: .bodyweight, priority: 6),
        .init(name: "Cable Crunch", pattern: .core, muscles: [.core], equipment: .cable, priority: 5),
        .init(name: "Ab Wheel Rollout", pattern: .core, muscles: [.core], equipment: .bodyweight, priority: 6),
        .init(name: "Dead Bug", pattern: .core, muscles: [.core], equipment: .bodyweight, priority: 3),
        // Conditioning
        .init(name: "Rowing Intervals", pattern: .conditioning, muscles: [.cardio, .fullBody], equipment: .cardioMachine, priority: 7),
        .init(name: "Incline Treadmill Walk", pattern: .conditioning, muscles: [.cardio], equipment: .cardioMachine, priority: 4),
        .init(name: "Assault Bike Sprints", pattern: .conditioning, muscles: [.cardio], equipment: .cardioMachine, priority: 7),
        .init(name: "Kettlebell Complex", pattern: .conditioning, muscles: [.fullBody, .cardio], equipment: .kettlebell, priority: 6),
        .init(name: "Burpees", pattern: .conditioning, muscles: [.fullBody, .cardio], equipment: .bodyweight, priority: 5),
        // Mobility (mapped to core pattern for scoring neutrality)
        .init(name: "World's Greatest Stretch", pattern: .core, muscles: [.fullBody], equipment: .bodyweight, priority: 2),
        .init(name: "Couch Stretch", pattern: .core, muscles: [.quads], equipment: .bodyweight, priority: 2),
        .init(name: "Thoracic Rotations", pattern: .core, muscles: [.core], equipment: .bodyweight, priority: 2)
    ]

    /// Patterns to hit per workout type, in order.
    private static func patternPlan(for type: WorkoutType) -> [MovementPattern] {
        switch type {
        case .fullBody, .strength, .hypertrophy:
            return [.squat, .horizontalPush, .horizontalPull, .hinge, .verticalPush, .core]
        case .upperLower:
            return [.horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .core]
        case .pushPullLegs:
            return [.horizontalPush, .verticalPush, .horizontalPull, .verticalPull, .squat, .hinge]
        case .conditioning:
            return [.conditioning, .conditioning, .core]
        case .mobility:
            return [.core, .core, .core]
        case .custom:
            return [.squat, .horizontalPush, .horizontalPull, .core]
        }
    }

    /// Sets/reps/rest/RPE scheme by type and phase.
    private static func scheme(for type: WorkoutType, phase: GoalPhase, isCompound: Bool) -> (sets: Int, reps: Int, rest: Int, rpe: Double) {
        switch type {
        case .strength:
            return isCompound ? (4, 5, 180, 8.5) : (3, 8, 120, 8)
        case .hypertrophy:
            return isCompound ? (4, 8, 120, 8) : (3, 12, 90, 8.5)
        case .conditioning:
            return (5, 0, 60, 8) // duration-based
        case .mobility:
            return (2, 0, 30, 5)
        default:
            let cutVolumePenalty = phase == .cut ? -1 : 0
            return isCompound ? (max(2, 3 + cutVolumePenalty), 6, 150, 8) : (3, 10, 90, 8)
        }
    }

    static func generate(request: GeneratorRequest) -> Workout {
        var plan = patternPlan(for: request.type)

        // Time budget: roughly 10 min per strength exercise, 8 per accessory.
        let maxExercises = max(2, min(plan.count, request.timeAvailableMinutes / 9))
        // High fatigue trims volume from the end (core/accessories survive, heavy compounds shrink below).
        if request.fatigueLevel >= 7 { plan = Array(plan.prefix(max(2, maxExercises - 2))) }
        else { plan = Array(plan.prefix(maxExercises)) }

        let workout = Workout(
            date: .now,
            title: generatedTitle(for: request),
            type: request.type,
            duration: Double(request.timeAvailableMinutes),
            notes: request.fatigueLevel >= 7 ? "Reduced volume: you reported high fatigue. Leave 2-3 reps in reserve." : "",
            completed: false
        )

        var usedNames = Set<String>()
        var order = 0
        for pattern in plan {
            var candidates = library.filter {
                $0.pattern == pattern &&
                request.availableEquipment.contains($0.equipment) &&
                !usedNames.contains($0.name)
            }
            if request.type == .mobility {
                candidates = candidates.filter { $0.priority <= 2 }
            }
            if !request.targetMuscles.isEmpty {
                let targeted = candidates.filter { !Set($0.muscles).isDisjoint(with: request.targetMuscles) }
                if !targeted.isEmpty { candidates = targeted }
            }
            guard var pick = candidates.max(by: { $0.priority < $1.priority }) else { continue }
            // Fatigued? Prefer a less demanding variation when one exists.
            if request.fatigueLevel >= 5, let easier = candidates.filter({ $0.priority < pick.priority }).max(by: { $0.priority < $1.priority }) {
                pick = easier
            }
            usedNames.insert(pick.name)

            let isCompound = pick.priority >= 7
            let s = scheme(for: request.type, phase: request.phase, isCompound: isCompound)
            let exercise = Exercise(
                name: pick.name,
                muscleGroups: pick.muscles,
                movementPattern: pick.pattern,
                equipment: pick.equipment,
                order: order,
                restSeconds: s.rest,
                targetRPE: s.rpe,
                notes: progressionNote(for: pick, type: request.type)
            )
            for setIndex in 0..<s.sets {
                let set = WorkoutSet(order: setIndex, reps: s.reps)
                if request.type == .conditioning { set.duration = 60 }
                if request.type == .mobility { set.duration = 45 }
                exercise.sets?.append(set)
            }
            workout.exercises?.append(exercise)
            order += 1
        }
        return workout
    }

    private static func generatedTitle(for request: GeneratorRequest) -> String {
        let day = Date().formatted(.dateTime.weekday(.wide))
        return "\(day) \(request.type.label)"
    }

    private static func progressionNote(for exercise: LibraryExercise, type: WorkoutType) -> String {
        switch type {
        case .strength:
            return "Add 2.5 kg when all sets hit target reps with a rep or two still in the tank."
        case .hypertrophy:
            return "Add a rep each session; add weight when top of rep range is reached."
        case .conditioning:
            return "Hold pace across intervals; extend work time before adding intensity."
        case .mobility:
            return "Slow, controlled. Breathe into end range."
        default:
            return exercise.priority >= 7 ? "Progress load once the sets start to feel easy." : "Chase quality reps, not load."
        }
    }
}
