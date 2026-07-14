import Foundation
import SwiftData

/// Decodes and caches restaurant / menu-item snapshots so the SwiftUI body
/// never re-runs `JSONDecoder` on every render pass. The saved/recent lists
/// access `record.restaurant` inside `ForEach` (for the row AND the
/// `NavigationLink(value:)` payload), which SwiftUI re-evaluates constantly;
/// decoding there froze the main thread. Snapshots are immutable for a given
/// id, so caching by id is safe. Main-thread-only access.
enum MenuSnapshotCache {
    private static var restaurants: [String: Restaurant] = [:]
    private static var items: [String: MenuItem] = [:]

    static func restaurant(id: String, data: Data) -> Restaurant? {
        if let cached = restaurants[id] { return cached }
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode(Restaurant.self, from: data) else { return nil }
        restaurants[id] = decoded
        return decoded
    }

    static func item(id: String, data: Data) -> MenuItem? {
        if let cached = items[id] { return cached }
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode(MenuItem.self, from: data) else { return nil }
        items[id] = decoded
        return decoded
    }
}

/// A restaurant the user explicitly saved. Stores a full encoded `Restaurant`
/// snapshot so saved restaurants render offline without re-querying a provider.
@Model
final class SavedRestaurantRecord {
    var restaurantID: String = ""
    var name: String = ""
    var city: String = ""
    var country: String = ""
    var savedAt: Date = Date()
    var snapshotData: Data = Data()

    init(restaurant: Restaurant) {
        self.restaurantID = restaurant.id
        self.name = restaurant.name
        self.city = restaurant.city
        self.country = restaurant.country
        self.savedAt = .now
        self.snapshotData = (try? JSONEncoder().encode(restaurant)) ?? Data()
    }

    var restaurant: Restaurant? { MenuSnapshotCache.restaurant(id: restaurantID, data: snapshotData) }
}

/// A menu item the user saved for quick re-logging later.
@Model
final class SavedMenuItemRecord {
    var itemID: String = ""
    var restaurantID: String = ""
    var name: String = ""
    var restaurantName: String = ""
    var savedAt: Date = Date()
    var snapshotData: Data = Data()

    init(item: MenuItem, restaurantName: String) {
        self.itemID = item.id
        self.restaurantID = item.restaurantID
        self.name = item.name
        self.restaurantName = restaurantName
        self.savedAt = .now
        self.snapshotData = (try? JSONEncoder().encode(item)) ?? Data()
    }

    var item: MenuItem? { MenuSnapshotCache.item(id: itemID, data: snapshotData) }
}

/// The user's own 1–5 star rating of a restaurant menu item. Menu items are
/// value structs re-fetched from providers (and AI lookups regenerate their
/// ids), so ratings live in their own store keyed by restaurant + normalized
/// item name (see `FoodRatingService.menuItemKey`) rather than by item id:
/// that way a rating survives a menu refresh that reshuffles ids.
@Model
final class MenuItemRatingRecord {
    /// Stable lookup key: `restaurantID|normalized item name`.
    var key: String = ""
    /// The item id at the time of rating; display/debug only, never matched on.
    var itemID: String = ""
    var restaurantID: String = ""
    var itemName: String = ""
    var restaurantName: String = ""
    /// 1–5; a rating cleared to 0 deletes the record instead.
    var rating: Int = 0
    var updatedAt: Date = Date()

    init(key: String, item: MenuItem, restaurantName: String, rating: Int) {
        self.key = key
        self.itemID = item.id
        self.restaurantID = item.restaurantID
        self.itemName = item.name
        self.restaurantName = restaurantName
        self.rating = rating
        self.updatedAt = .now
    }

    /// Import path: rebuilds a record straight from snapshot fields.
    init(key: String, itemID: String, restaurantID: String, itemName: String,
         restaurantName: String, rating: Int, updatedAt: Date) {
        self.key = key
        self.itemID = itemID
        self.restaurantID = restaurantID
        self.itemName = itemName
        self.restaurantName = restaurantName
        self.rating = rating
        self.updatedAt = updatedAt
    }
}

/// A restaurant the user recently opened. Trimmed to a small rolling window by
/// `MenuCheckerLibrary`.
@Model
final class RecentRestaurantRecord {
    var restaurantID: String = ""
    var name: String = ""
    var viewedAt: Date = Date()
    var snapshotData: Data = Data()

    init(restaurant: Restaurant) {
        self.restaurantID = restaurant.id
        self.name = restaurant.name
        self.viewedAt = .now
        self.snapshotData = (try? JSONEncoder().encode(restaurant)) ?? Data()
    }

    var restaurant: Restaurant? { MenuSnapshotCache.restaurant(id: restaurantID, data: snapshotData) }
}
