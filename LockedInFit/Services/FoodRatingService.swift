import Foundation
import SwiftData

/// One place for every food-rating rule: the star scale and the stable key
/// plus upsert logic for restaurant menu items. All three rating surfaces
/// (logged meals, presets, Menu Checker items) share the scale defined here,
/// but each is otherwise deliberately independent: rating a logged meal says
/// "that meal was good," rating a preset says "this food is a keeper," and
/// neither ever writes to the other.
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
}
