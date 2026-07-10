import Foundation
import SwiftData

/// Keeps Exercise Presets in sync with what actually gets logged, the same
/// way FoodPresetSyncService does for meals: every exercise added to a
/// workout that isn't already a saved preset (by name) becomes one
/// automatically once the workout is saved, so presets build themselves up
/// from real training instead of requiring a separate manual step.
enum ExercisePresetSyncService {
    /// Case-insensitive match on a normalized name — the one notion of
    /// "already have this exercise" shared by both directions of the sync:
    /// skipping a duplicate preset add, and preferring a saved preset's own
    /// numbers over a fresh AI estimate for the same exercise. See
    /// FoodPresetSyncService.matchingPreset for why both sides need
    /// normalizing, not just the incoming name.
    static func matchingPreset(named name: String, in presets: [ExercisePreset]) -> ExercisePreset? {
        let target = FoodPresetSyncService.normalize(name)
        guard !target.isEmpty else { return nil }
        return presets.first { FoodPresetSyncService.normalize($0.name) == target }
    }

    /// Adds a preset for every exercise that doesn't already match one by
    /// name. Call once per saved workout, over its final exercise list (see
    /// WorkoutLogView's save/finish points), so an exercise added then
    /// deleted before the workout was ever saved never creates a preset.
    /// Typical prescription (sets/reps/weight/duration/distance) is taken
    /// from the exercise's own first logged set, matching how a preset's
    /// prescription is applied uniformly to every set when it's added to a
    /// future workout.
    static func addMissingPresets(for exercises: [Exercise], existingPresets: [ExercisePreset], context: ModelContext) {
        var known = existingPresets
        for exercise in exercises {
            guard matchingPreset(named: exercise.name, in: known) == nil else { continue }
            let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let firstSet = exercise.setList.first
            let preset = ExercisePreset(
                name: name,
                muscleGroups: exercise.muscleGroups,
                movementPattern: exercise.movementPattern,
                equipment: exercise.equipment,
                restSeconds: exercise.restSeconds,
                targetRPE: exercise.targetRPE,
                notes: exercise.notes,
                setCount: max(1, exercise.setList.count),
                reps: firstSet?.reps ?? 8,
                weightKg: firstSet?.weight ?? 0,
                durationSeconds: firstSet?.duration ?? 0,
                distanceMeters: firstSet?.distance ?? 0)
            context.insert(preset)
            // So two exercises of the same name within one workout only
            // ever produce one preset, not one per occurrence.
            known.append(preset)
        }
    }
}
