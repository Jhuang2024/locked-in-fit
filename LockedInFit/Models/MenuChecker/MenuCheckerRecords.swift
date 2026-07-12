import Foundation
import SwiftData

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

    var restaurant: Restaurant? {
        guard !snapshotData.isEmpty else { return nil }
        return try? JSONDecoder().decode(Restaurant.self, from: snapshotData)
    }
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

    var item: MenuItem? {
        guard !snapshotData.isEmpty else { return nil }
        return try? JSONDecoder().decode(MenuItem.self, from: snapshotData)
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

    var restaurant: Restaurant? {
        guard !snapshotData.isEmpty else { return nil }
        return try? JSONDecoder().decode(Restaurant.self, from: snapshotData)
    }
}
