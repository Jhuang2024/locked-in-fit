import Foundation

/// Facade the UI talks to for discovery and menus. Combines the (swappable)
/// restaurant + menu providers with the shared cache and returns freshness
/// metadata so screens can show "updated X ago" and refresh stale data.
struct MenuCheckerRepository {
    var restaurantProvider: RestaurantProvider
    var menuProvider: MenuProvider
    var cache: MenuCheckerCache = .shared
    /// How long a cached menu is treated as current before we mark it stale.
    var menuMaxAge: TimeInterval = 60 * 30

    init(settings: UserSettings?) {
        self.restaurantProvider = MenuCheckerProviderFactory.restaurantProvider(settings: settings)
        self.menuProvider = MenuCheckerProviderFactory.menuProvider(settings: settings)
    }

    init(restaurantProvider: RestaurantProvider, menuProvider: MenuProvider) {
        self.restaurantProvider = restaurantProvider
        self.menuProvider = menuProvider
    }

    func nearby(origin: GeoPoint, filters: RestaurantFilters) async throws -> [Restaurant] {
        try await restaurantProvider.nearby(origin: origin, filters: filters)
    }

    func search(_ query: RestaurantQuery) async throws -> [Restaurant] {
        let key = cacheKey(for: query)
        if let cached = await cache.search(key), !cached.isStale(maxAge: 60 * 5) {
            return cached.value
        }
        let results = try await restaurantProvider.search(query)
        await cache.storeSearch(results, for: key)
        return results
    }

    /// Load a menu, using the cache when fresh. Returns the items plus whether
    /// they came from a stale cache (so the UI can show a "may be out of date"
    /// note) and when they were fetched.
    func menu(for restaurant: Restaurant, forceRefresh: Bool = false) async throws -> (items: [MenuItem], fetchedAt: Date, stale: Bool) {
        if !forceRefresh, let cached = await cache.menu(for: restaurant.id) {
            return (cached.value, cached.fetchedAt, cached.isStale(maxAge: menuMaxAge))
        }
        let items = try await menuProvider.menu(for: restaurant)
        await cache.storeMenu(items, for: restaurant.id)
        return (items, .now, false)
    }

    /// Average Health Score across a menu for a given profile — used to fill in
    /// the restaurant's headline "avg menu health" figure from real items.
    static func averageHealthScore(items: [MenuItem], profile: ScoringProfile) -> Double? {
        guard !items.isEmpty else { return nil }
        let scores = items.map { MenuItemResolver.resolve(item: $0, profile: profile).healthScore }
        return (scores.reduce(0, +) / Double(scores.count)).rounded()
    }

    private func cacheKey(for query: RestaurantQuery) -> String {
        var parts = [query.text.lowercased(), query.worldwide ? "world" : "near"]
        if let o = query.origin { parts.append("\(Int(o.latitude * 100)),\(Int(o.longitude * 100))") }
        if query.filters.isActive { parts.append("f") }
        return parts.joined(separator: "|")
    }
}
