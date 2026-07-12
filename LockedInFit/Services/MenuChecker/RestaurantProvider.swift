import Foundation

/// Filters applied to restaurant discovery and, where relevant, menu items.
/// Distance/open/price/dietary/official filter restaurants directly; the macro
/// and score filters (calories, protein, health, satiety) also drive menu-item
/// filtering on the restaurant screen.
struct RestaurantFilters: Equatable {
    var maxDistanceMeters: Double? = nil
    var cuisines: Set<String> = []
    var openNow: Bool = false
    var maxCalories: Double? = nil
    var minProtein: Double? = nil
    var minHealthScore: Double? = nil
    var minSatietyScore: Double? = nil
    var dietary: Set<DietaryTag> = []
    var maxPrice: PriceLevel? = nil
    var officialNutritionOnly: Bool = false

    static let none = RestaurantFilters()

    var isActive: Bool {
        maxDistanceMeters != nil || !cuisines.isEmpty || openNow || maxCalories != nil ||
        minProtein != nil || minHealthScore != nil || minSatietyScore != nil ||
        !dietary.isEmpty || maxPrice != nil || officialNutritionOnly
    }

    /// Restaurant-level pass: everything except the per-item macro/score filters.
    func matches(_ restaurant: Restaurant, origin: GeoPoint?, now: Date = .now) -> Bool {
        if let maxDist = maxDistanceMeters, let d = restaurant.distanceMeters(from: origin), d > maxDist {
            return false
        }
        if !cuisines.isEmpty {
            let rc = Set(restaurant.cuisines.map { $0.lowercased() })
            if cuisines.map({ $0.lowercased() }).allSatisfy({ !rc.contains($0) }) { return false }
        }
        if openNow, restaurant.isOpen(at: now) == false { return false }
        if let maxPrice, restaurant.priceLevel != .unknown, restaurant.priceLevel > maxPrice { return false }
        if officialNutritionOnly, !restaurant.hasOfficialNutrition { return false }
        if !dietary.isEmpty {
            let rt = Set(restaurant.dietaryTags)
            if !dietary.isSubset(of: rt) { return false }
        }
        if let minHealth = minHealthScore, let avg = restaurant.averageMenuHealthScore, avg < minHealth {
            return false
        }
        return true
    }
}

/// A restaurant search request. `origin` powers distance sorting/filtering and
/// may be nil when the user searches by name/place without granting location.
struct RestaurantQuery: Equatable {
    var text: String = ""
    var origin: GeoPoint? = nil
    var filters: RestaurantFilters = .none
    /// When true, search the whole world; otherwise bias to `origin`.
    var worldwide: Bool = false
}

/// Errors surfaced to the UI so it can degrade gracefully rather than crash.
enum MenuCheckerError: LocalizedError, Equatable {
    case noInternet
    case unsupportedRegion
    case menuUnavailable
    case providerFailure(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .noInternet: return "You appear to be offline. Showing what's cached; search needs a connection."
        case .unsupportedRegion: return "Restaurant data isn't available in this region yet. Try manual search."
        case .menuUnavailable: return "This restaurant hasn't published a menu we can read."
        case .providerFailure(let msg): return "Couldn't load restaurants: \(msg)"
        case .notFound: return "No matching restaurants found."
        }
    }
}

/// Restaurant discovery/search source. Kept behind a protocol so the underlying
/// data (Google Places, Yelp, Foursquare, a nutrition DB, or our mock) can be
/// swapped without touching the UI. Restaurant search and menu data are separate
/// protocols precisely because they often come from different providers.
protocol RestaurantProvider {
    var name: String { get }
    func nearby(origin: GeoPoint, filters: RestaurantFilters) async throws -> [Restaurant]
    func search(_ query: RestaurantQuery) async throws -> [Restaurant]
}

/// Menu retrieval source, independent of the restaurant provider.
protocol MenuProvider {
    var name: String { get }
    func menu(for restaurant: Restaurant) async throws -> [MenuItem]
}

extension Array where Element == Restaurant {
    /// Merge duplicate listings (same place from different providers) keeping the
    /// record with the most information (official nutrition, then more cuisines).
    func deduplicated() -> [Restaurant] {
        var byKey: [String: Restaurant] = [:]
        for r in self {
            if let existing = byKey[r.dedupeKey] {
                let better = (r.hasOfficialNutrition && !existing.hasOfficialNutrition)
                    || (r.cuisines.count > existing.cuisines.count)
                if better { byKey[r.dedupeKey] = r }
            } else {
                byKey[r.dedupeKey] = r
            }
        }
        return Array(byKey.values)
    }

    /// Sort by distance from origin when known, else alphabetically.
    func sortedByDistance(from origin: GeoPoint?) -> [Restaurant] {
        guard let origin else { return sorted { $0.name < $1.name } }
        return sorted {
            ($0.location.distance(to: origin)) < ($1.location.distance(to: origin))
        }
    }
}
