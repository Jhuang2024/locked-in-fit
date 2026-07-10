import Foundation
import SwiftData

/// Keeps Food Presets in sync with what actually gets logged: every food
/// item in a newly-logged meal that isn't already a saved preset (by name)
/// becomes one automatically, so presets build themselves up from real
/// usage instead of requiring a separate manual step.
enum FoodPresetSyncService {
    /// Case-insensitive match on a normalized name — the one notion of
    /// "already have this food" shared by both directions of the sync:
    /// skipping a duplicate preset add, and preferring a saved preset's own
    /// numbers over a fresh AI estimate for the same food. Normalizing both
    /// sides (not just the incoming name) matters: a preset typed by hand
    /// with a trailing space, or an AI estimate that adds a stray period or
    /// double space, used to silently never match again — every AI
    /// rephrasing ("white rice" vs "steamed rice," vs "Rice") created a new
    /// preset instead of reusing the saved one, which is what actually made
    /// this feature feel unreliable rather than automatic.
    static func matchingPreset(named name: String, in presets: [FoodPreset]) -> FoodPreset? {
        let target = normalize(name)
        guard !target.isEmpty else { return nil }
        return presets.first { normalize($0.name) == target }
    }

    /// Trims, collapses internal whitespace runs to a single space, and
    /// drops trailing punctuation, then case-folds. Only strips *formatting*
    /// noise — it never bridges genuinely different wording ("chicken
    /// breast" vs "chicken thigh" still won't match), so it can't cause a
    /// false match between two actually-different foods.
    static func normalize(_ raw: String) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!"))
            .lowercased()
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
                referenceGrams: item.grams,
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
