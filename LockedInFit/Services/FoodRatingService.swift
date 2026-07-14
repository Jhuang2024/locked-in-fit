import Foundation
import SwiftData

/// One place for every food-rating rule: the star scale, the stable key for
/// restaurant menu items, upserting menu-item ratings, and the sync that
/// carries a logged meal's rating over to its matching food presets. All three
/// rating surfaces (logged meals, presets, Menu Checker items) go through here
/// so they can never drift apart on normalization or scale.
enum FoodRatingService {
    /// Ratings are 1–5 stars everywhere; 0 always means "not rated".
    static let maxRating = 5

    static func clamped(_ rating: Int) -> Int {
        min(max(rating, 0), maxRating)
    }

    // MARK: - Menu items

    /// Stable identity for a menu item's rating. Item ids are NOT stable: the
    /// AI menu lookup bakes a running index and lookup tier into them, so a
    /// menu refresh can reassign every id while the dishes stay the same.
    /// Restaurant id + normalized dish name is what actually identifies "that
    /// dish at that place" across refreshes. Reuses the same normalizer as the
    /// preset sync so "Pad Thai " and "pad thai" are one dish here too.
    static func menuItemKey(restaurantID: String, itemName: String) -> String {
        restaurantID + "|" + FoodPresetSyncService.normalize(itemName)
    }

    static func rating(for item: MenuItem, in records: [MenuItemRatingRecord]) -> Int {
        let key = menuItemKey(restaurantID: item.restaurantID, itemName: item.name)
        return records.first { $0.key == key }?.rating ?? 0
    }

    /// Upsert the user's rating for a menu item. Clearing to 0 deletes the
    /// record outright so unrated items don't accumulate empty rows.
    static func setRating(_ rating: Int, for item: MenuItem, restaurantName: String,
                          records: [MenuItemRatingRecord], context: ModelContext) {
        let value = clamped(rating)
        let key = menuItemKey(restaurantID: item.restaurantID, itemName: item.name)
        if let existing = records.first(where: { $0.key == key }) {
            if value == 0 {
                context.delete(existing)
            } else {
                existing.rating = value
                existing.updatedAt = .now
                existing.itemID = item.id
                existing.restaurantName = restaurantName
            }
        } else if value > 0 {
            context.insert(MenuItemRatingRecord(key: key, item: item,
                                                restaurantName: restaurantName, rating: value))
        }
        try? context.save()
    }

    // MARK: - Logged meals → presets

    /// Rating a logged meal also rates the presets for the foods in it
    /// (matched by the same normalized name the preset sync uses, so this
    /// finds the presets that `FoodPresetSyncService.addMissingPresets`
    /// auto-created from this very meal). This is what makes "rate what you
    /// logged" feed the preset sorter without a separate rating pass.
    /// Clearing a meal's rating leaves preset ratings alone: the preset may
    /// have earned its stars from other meals.
    static func syncPresetRatings(from meal: MealLog, presets: [FoodPreset]) {
        let value = clamped(meal.rating)
        guard value > 0 else { return }
        for item in meal.items {
            FoodPresetSyncService.matchingPreset(named: item.name, in: presets)?.rating = value
        }
    }
}
