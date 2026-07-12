import Foundation
import MapKit

/// Real restaurant discovery via Apple Maps (`MKLocalSearch`). Needs no API key
/// — it uses the device's built-in Maps access. Provides name, location,
/// address, phone, website, and a coarse category; it does NOT provide menus,
/// hours, price, or nutrition, so those are left empty/unknown and filled by the
/// menu/nutrition providers (sample menus, then the AI estimate).
struct MapKitRestaurantProvider: RestaurantProvider {
    let name = "Apple Maps"

    private static let categories: [MKPointOfInterestCategory] = [.restaurant, .cafe, .bakery, .brewery]

    func nearby(origin: GeoPoint, filters: RestaurantFilters) async throws -> [Restaurant] {
        let radius = min(max(filters.maxDistanceMeters ?? 5000, 500), 50000)
        let request = MKLocalPointsOfInterestRequest(
            center: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude),
            radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.categories)
        let response = try await MKLocalSearch(request: request).start()
        let restaurants = response.mapItems.map { restaurant(from: $0) }
        return restaurants
            .deduplicated()
            .filter { filters.matches($0, origin: origin) }
            .sortedByDistance(from: origin)
    }

    func search(_ query: RestaurantQuery) async throws -> [Restaurant] {
        let request = MKLocalSearch.Request()
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        request.naturalLanguageQuery = text.isEmpty ? "restaurant" : text
        request.resultTypes = .pointOfInterest
        if let origin = query.origin, !query.worldwide {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude),
                latitudinalMeters: 30000, longitudinalMeters: 30000)
        }
        let response = try await MKLocalSearch(request: request).start()
        let restaurants = response.mapItems.map { restaurant(from: $0) }.deduplicated()
        let filtered = restaurants.filter { query.filters.matches($0, origin: query.origin) }
        if query.worldwide || query.origin == nil {
            return filtered.sorted { $0.name < $1.name }
        }
        return filtered.sortedByDistance(from: query.origin)
    }

    // MARK: Mapping

    private func restaurant(from item: MKMapItem) -> Restaurant {
        let placemark = item.placemark
        let coord = placemark.coordinate
        let name = item.name ?? placemark.name ?? "Restaurant"
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }.joined(separator: " ")
        let address = street.isEmpty ? (placemark.title ?? "") : street
        return Restaurant(
            id: "mapkit:" + stableID(name: name, coord: coord),
            name: name,
            cuisines: [cuisine(for: item.pointOfInterestCategory)],
            address: address,
            city: placemark.locality ?? placemark.administrativeArea ?? "",
            country: placemark.country ?? "",
            location: GeoPoint(latitude: coord.latitude, longitude: coord.longitude),
            priceLevel: .unknown,
            // Apple Maps doesn't return opening hours here, so leave them empty
            // (isOpen() → nil) rather than inventing a schedule.
            hours: WeeklyHours(days: [:]),
            phone: item.phoneNumber,
            website: item.url?.absoluteString,
            currencyCode: currency(for: placemark.isoCountryCode),
            hasOfficialNutrition: false,
            averageMenuHealthScore: nil,
            providerName: "Apple Maps",
            dietaryTags: [],
            photoAssetName: nil)
    }

    /// A stable id from name + coordinate (rounded), so saved/recent/cart
    /// references survive across separate searches.
    private func stableID(name: String, coord: CLLocationCoordinate2D) -> String {
        let cleanName = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let lat = (coord.latitude * 10000).rounded() / 10000
        let lon = (coord.longitude * 10000).rounded() / 10000
        return "\(cleanName)@\(lat),\(lon)"
    }

    private func cuisine(for category: MKPointOfInterestCategory?) -> String {
        switch category {
        case .some(.cafe): return "Café"
        case .some(.bakery): return "Bakery"
        case .some(.brewery): return "Brewery"
        case .some(.foodMarket): return "Food Market"
        default: return "Restaurant"
        }
    }

    private func currency(for isoCountryCode: String?) -> String {
        let map: [String: String] = [
            "US": "USD", "CN": "CNY", "GB": "GBP", "JP": "JPY", "HK": "HKD",
            "AU": "AUD", "CA": "CAD", "FR": "EUR", "DE": "EUR", "IT": "EUR",
            "ES": "EUR", "TH": "THB", "SG": "SGD", "KR": "KRW", "IN": "INR",
            "TW": "TWD", "MY": "MYR", "NZ": "NZD", "CH": "CHF", "AE": "AED"]
        if let code = isoCountryCode, let currency = map[code.uppercased()] { return currency }
        return Locale.current.currency?.identifier ?? "USD"
    }
}
