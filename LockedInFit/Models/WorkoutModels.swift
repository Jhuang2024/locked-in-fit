import Foundation
import SwiftData

@Model
final class Workout {
    var date: Date = Date()
    var title: String = ""
    var typeRaw: String = WorkoutType.custom.rawValue
    /// Minutes.
    var duration: Double = 0
    @Relationship(deleteRule: .cascade) var exercises: [Exercise]? = []
    var notes: String = ""
    /// 1–10 subjective difficulty.
    var perceivedDifficulty: Int = 0
    var completed: Bool = false
    var isTemplate: Bool = false
    /// Calories burned by this specific workout: manually entered, from an AI
    /// description estimate, or (if left at 0) defaulted from the duration/
    /// type/RPE heuristic when the workout is finished.
    var caloriesBurned: Double = 0

    var type: WorkoutType {
        get { WorkoutType(rawValue: typeRaw) ?? .custom }
        set { typeRaw = newValue.rawValue }
    }

    var exerciseList: [Exercise] { (exercises ?? []).sorted { $0.order < $1.order } }

    var totalVolume: Double {
        exerciseList.reduce(0) { sum, ex in
            sum + ex.setList.reduce(0) { $0 + ($1.completed ? $1.weight * Double($1.reps) : 0) }
        }
    }

    init(date: Date = .now,
         title: String,
         type: WorkoutType,
         duration: Double = 0,
         notes: String = "",
         perceivedDifficulty: Int = 0,
         completed: Bool = false,
         isTemplate: Bool = false) {
        self.date = date
        self.title = title
        self.typeRaw = type.rawValue
        self.duration = duration
        self.notes = notes
        self.perceivedDifficulty = perceivedDifficulty
        self.completed = completed
        self.isTemplate = isTemplate
        self.exercises = []
    }
}

@Model
final class Exercise {
    var name: String = ""
    var muscleGroupsRaw: [String] = []
    var movementPatternRaw: String = MovementPattern.horizontalPush.rawValue
    var equipmentRaw: String = Equipment.barbell.rawValue
    var order: Int = 0
    /// Suggested rest between sets, seconds.
    var restSeconds: Int = 90
    var targetRPE: Double = 8
    var notes: String = ""
    @Relationship(deleteRule: .cascade) var sets: [WorkoutSet]? = []
    var workout: Workout?

    var movementPattern: MovementPattern {
        get { MovementPattern(rawValue: movementPatternRaw) ?? .horizontalPush }
        set { movementPatternRaw = newValue.rawValue }
    }
    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .barbell }
        set { equipmentRaw = newValue.rawValue }
    }
    var muscleGroups: [MuscleGroup] {
        get { muscleGroupsRaw.compactMap { MuscleGroup(rawValue: $0) } }
        set { muscleGroupsRaw = newValue.map(\.rawValue) }
    }
    var setList: [WorkoutSet] { (sets ?? []).sorted { $0.order < $1.order } }

    var bestSet: WorkoutSet? {
        setList.filter(\.completed).max { StrengthScoreCalculator.epley1RM(weight: $0.weight, reps: $0.reps) < StrengthScoreCalculator.epley1RM(weight: $1.weight, reps: $1.reps) }
    }

    init(name: String,
         muscleGroups: [MuscleGroup] = [],
         movementPattern: MovementPattern,
         equipment: Equipment,
         order: Int = 0,
         restSeconds: Int = 90,
         targetRPE: Double = 8,
         notes: String = "") {
        self.name = name
        self.muscleGroupsRaw = muscleGroups.map(\.rawValue)
        self.movementPatternRaw = movementPattern.rawValue
        self.equipmentRaw = equipment.rawValue
        self.order = order
        self.restSeconds = restSeconds
        self.targetRPE = targetRPE
        self.notes = notes
        self.sets = []
    }
}

@Model
final class WorkoutSet {
    var order: Int = 0
    var reps: Int = 0
    /// kg
    var weight: Double = 0
    /// Seconds, for timed work.
    var duration: Double = 0
    /// Meters, for conditioning.
    var distance: Double = 0
    var rpe: Double = 0
    var completed: Bool = false
    var exercise: Exercise?

    init(order: Int = 0, reps: Int = 0, weight: Double = 0, duration: Double = 0, distance: Double = 0, rpe: Double = 0, completed: Bool = false) {
        self.order = order
        self.reps = reps
        self.weight = weight
        self.duration = duration
        self.distance = distance
        self.rpe = rpe
        self.completed = completed
    }
}

/// A saved exercise, analogous to FoodPreset: everything usually logged for
/// a pre-existing exercise (its classification plus a typical prescription),
/// so re-adding the same exercise later — by picking it or describing it —
/// doesn't require re-entering or re-estimating the same numbers. Built
/// automatically from what's actually logged (see ExercisePresetSyncService)
/// as well as manually from the Exercise Presets screen.
@Model
final class ExercisePreset {
    var name: String = ""
    var muscleGroupsRaw: [String] = []
    var movementPatternRaw: String = MovementPattern.horizontalPush.rawValue
    var equipmentRaw: String = Equipment.barbell.rawValue
    var restSeconds: Int = 90
    var targetRPE: Double = 8
    var notes: String = ""
    /// Typical prescription applied when this preset is added to a workout.
    var setCount: Int = 3
    var reps: Int = 8
    /// kg
    var weightKg: Double = 0
    /// Seconds, for timed work (movementPattern == .conditioning).
    var durationSeconds: Double = 0
    /// Meters, for distance-based conditioning work.
    var distanceMeters: Double = 0

    var movementPattern: MovementPattern {
        get { MovementPattern(rawValue: movementPatternRaw) ?? .horizontalPush }
        set { movementPatternRaw = newValue.rawValue }
    }
    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .barbell }
        set { equipmentRaw = newValue.rawValue }
    }
    var muscleGroups: [MuscleGroup] {
        get { muscleGroupsRaw.compactMap { MuscleGroup(rawValue: $0) } }
        set { muscleGroupsRaw = newValue.map(\.rawValue) }
    }

    init(name: String,
         muscleGroups: [MuscleGroup] = [],
         movementPattern: MovementPattern,
         equipment: Equipment,
         restSeconds: Int = 90,
         targetRPE: Double = 8,
         notes: String = "",
         setCount: Int = 3,
         reps: Int = 8,
         weightKg: Double = 0,
         durationSeconds: Double = 0,
         distanceMeters: Double = 0) {
        self.name = name
        self.muscleGroupsRaw = muscleGroups.map(\.rawValue)
        self.movementPatternRaw = movementPattern.rawValue
        self.equipmentRaw = equipment.rawValue
        self.restSeconds = restSeconds
        self.targetRPE = targetRPE
        self.notes = notes
        self.setCount = setCount
        self.reps = reps
        self.weightKg = weightKg
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
    }
}

@Model
final class StrengthScore {
    var movementRaw: String = MovementPattern.squat.rawValue
    /// 0–1000
    var score: Double = 0
    var levelName: String = "Untrained"
    /// Points change over the last ~30 days.
    var trend: Double = 0
    var bestSetSummary: String = ""
    var estimated1RM: Double = 0
    var volumeTrend: Double = 0
    var consistencyStreak: Int = 0
    var lastUpdated: Date = Date()

    var movement: MovementPattern {
        get { MovementPattern(rawValue: movementRaw) ?? .squat }
        set { movementRaw = newValue.rawValue }
    }

    init(movement: MovementPattern) {
        self.movementRaw = movement.rawValue
    }
}
