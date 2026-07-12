import Foundation

/// Offline restaurant provider backed by `SampleMenuData`. Simulates a small
/// network delay and supports nearby + worldwide text search (by name, cuisine,
/// city, country, address, and dish name).
struct MockRestaurantProvider: RestaurantProvider {
    let name = "Locked In Sample"

    func nearby(origin: GeoPoint, filters: RestaurantFilters) async throws -> [Restaurant] {
        try await Task.sleep(for: .milliseconds(250))
        return SampleMenuData.restaurants
            .filter { filters.matches($0, origin: origin) }
            .sortedByDistance(from: origin)
    }

    func search(_ query: RestaurantQuery) async throws -> [Restaurant] {
        try await Task.sleep(for: .milliseconds(300))
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var results = SampleMenuData.restaurants

        if !text.isEmpty {
            results = results.filter { restaurant in
                matches(restaurant, text: text)
            }
        }
        results = results.filter { query.filters.matches($0, origin: query.origin) }
        let deduped = results.deduplicated()
        if query.worldwide || query.origin == nil {
            return deduped.sorted { $0.name < $1.name }
        }
        return deduped.sortedByDistance(from: query.origin)
    }

    private func matches(_ r: Restaurant, text: String) -> Bool {
        if r.name.lowercased().contains(text) { return true }
        if r.city.lowercased().contains(text) || r.country.lowercased().contains(text) { return true }
        if r.address.lowercased().contains(text) { return true }
        if r.cuisines.contains(where: { $0.lowercased().contains(text) }) { return true }
        // Dish search: does any menu item name/description match?
        let menu = SampleMenuData.menu(for: r)
        return menu.contains { $0.name.lowercased().contains(text) || $0.itemDescription.lowercased().contains(text) }
    }
}

/// Offline menu provider. Throws `menuUnavailable` for restaurants that publish
/// no readable menu, so the UI can show a graceful empty state.
struct MockMenuProvider: MenuProvider {
    let name = "Locked In Sample"

    func menu(for restaurant: Restaurant) async throws -> [MenuItem] {
        try await Task.sleep(for: .milliseconds(200))
        let items = SampleMenuData.menu(for: restaurant)
        if items.isEmpty { throw MenuCheckerError.menuUnavailable }
        return items
    }
}

/// Chooses restaurant / menu providers. Today only the offline sample provider
/// exists, but everything is behind protocols so a live provider (Google Places,
/// Yelp, a nutrition DB) can be dropped in without touching callers.
enum MenuCheckerProviderFactory {
    static func restaurantProvider(settings: UserSettings?) -> RestaurantProvider {
        MockRestaurantProvider()
    }
    static func menuProvider(settings: UserSettings?) -> MenuProvider {
        MockMenuProvider()
    }
}

/// A cached payload with the time it was fetched, so the UI can show "updated
/// 3 min ago" and never present very stale data as current.
struct CachedResult<T> {
    var value: T
    var fetchedAt: Date

    func isStale(maxAge: TimeInterval) -> Bool { Date().timeIntervalSince(fetchedAt) > maxAge }
    var ageDescription: String {
        let seconds = Int(Date().timeIntervalSince(fetchedAt))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        return "\(seconds / 3600) h ago"
    }
}

/// In-memory cache for restaurant lists and menus keyed by request, with fetch
/// timestamps. Reduces repeated provider calls while the session is alive;
/// timestamps let the UI avoid presenting stale data as fresh.
actor MenuCheckerCache {
    static let shared = MenuCheckerCache()

    private var menus: [String: CachedResult<[MenuItem]>] = [:]
    private var searches: [String: CachedResult<[Restaurant]>] = [:]

    func menu(for restaurantID: String) -> CachedResult<[MenuItem]>? { menus[restaurantID] }
    func storeMenu(_ items: [MenuItem], for restaurantID: String) {
        menus[restaurantID] = CachedResult(value: items, fetchedAt: .now)
    }

    func search(_ key: String) -> CachedResult<[Restaurant]>? { searches[key] }
    func storeSearch(_ results: [Restaurant], for key: String) {
        searches[key] = CachedResult(value: results, fetchedAt: .now)
    }

    func clear() { menus.removeAll(); searches.removeAll() }
}
