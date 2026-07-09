import Foundation
import SwiftData

/// Keeps Food Presets in sync with what actually gets logged: every food
/// item in a newly-logged meal that isn't already a saved preset (by name)
/// becomes one automatically, so presets build themselves up from real
/// usage instead of requiring a separate manual step.
enum FoodPresetSyncService {
    /// Case-insensitive, whitespace-trimmed exact name match — the one
    /// notion of "already have this food" shared by both directions of the
    /// sync: skipping a duplicate preset add, and preferring a saved
    /// preset's own numbers over a fresh AI estimate for the same food.
    static func matchingPreset(named name: String, in presets: [FoodPreset]) -> FoodPreset? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        return presets.first { $0.name.caseInsensitiveCompare(target) == .orderedSame }
    }

    /// Adds a preset for every item that doesn't already match one by name.
    /// Call once per logged meal, after its food items are known (and,
    /// for AI estimates, after `MealEstimate.FoodItemEstimate.makeFoodItem`
    /// has already substituted in any matching preset's values — matching
    /// against `existingPresets` again here is what keeps that substituted
    /// item from being re-added as a "new" preset of itself).
    static func addMissingPresets(for items: [FoodItem], existingPresets: [FoodPreset], context: ModelContext) {
        var known = existingPresets
        for item in items {
            guard matchingPreset(named: item.name, in: known) == nil else { continue }
            let serving = item.grams > 0 ? "\(Int(item.grams.rounded())) g" : ""
            let preset = FoodPreset(
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                serving: serving,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fat: item.fat,
                fiber: item.fiber,
                sodium: item.sodium,
                cookingMethod: item.cookingMethod)
            guard !preset.name.isEmpty else { continue }
            context.insert(preset)
            // So two items of the same food within one meal (e.g. two
            // separate "rice" entries from a multi-photo estimate) only
            // ever produce one preset, not one per occurrence.
            known.append(preset)
        }
    }
}
