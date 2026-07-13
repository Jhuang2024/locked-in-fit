import Foundation

/// Opening hours for a single weekday, in minutes-from-midnight local time.
/// A `nil` interval means closed that day. Overnight spans (e.g. 18:00–02:00)
/// are represented by `closeMinute < openMinute` and handled in `isOpen`.
struct DayHours: Codable, Equatable, Hashable {
    var openMinute: Int
    var closeMinute: Int

    func contains(minute: Int) -> Bool {
        if closeMinute >= openMinute {
            return minute >= openMinute && minute < closeMinute
        } else {
            // Overnight: open late, closes after midnight.
            return minute >= openMinute || minute < closeMinute
        }
    }

    var displayString: String {
        Self.format(openMinute) + "–" + Self.format(closeMinute)
    }
    private static func format(_ minute: Int) -> String {
        let h = (minute / 60) % 24
        let m = minute % 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "AM" : "PM"
        return m == 0 ? "\(hour12) \(ampm)" : String(format: "%d:%02d %@", hour12, m, ampm)
    }
}

/// A week of opening hours keyed by `Calendar` weekday (1 = Sunday … 7 = Saturday).
struct WeeklyHours: Codable, Equatable, Hashable {
    /// weekday(1–7) -> hours, missing key = closed that day.
    var days: [Int: DayHours]

    init(days: [Int: DayHours] = [:]) { self.days = days }

    /// Same hours every day of the week: the common case for our sample data.
    static func everyDay(open: Int, close: Int) -> WeeklyHours {
        var d: [Int: DayHours] = [:]
        for wd in 1...7 { d[wd] = DayHours(openMinute: open, closeMinute: close) }
        return WeeklyHours(days: d)
    }

    func isOpen(at date: Date, calendar: Calendar = .current) -> Bool? {
        guard !days.isEmpty else { return nil }
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = comps.weekday else { return nil }
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if let today = days[wd], today.contains(minute: minute) { return true }
        // Handle an overnight span that began yesterday.
        let yesterday = wd == 1 ? 7 : wd - 1
        if let prev = days[yesterday], prev.closeMinute < prev.openMinute, minute < prev.closeMinute {
            return true
        }
        return false
    }

    func todayString(for date: Date, calendar: Calendar = .current) -> String {
        let wd = calendar.component(.weekday, from: date)
        guard let today = days[wd] else { return "Closed today" }
        return today.displayString
    }
}

/// A restaurant as returned by a `RestaurantProvider`. This is provider-agnostic:
/// Google Places, Yelp, a nutrition database, or our mock all map into this shape.
struct Restaurant: Identifiable, Codable, Equatable, Hashable {
    /// Stable provider id, namespaced by provider to keep de-duplication sane.
    var id: String
    var name: String
    var cuisines: [String]
    var address: String
    var city: String
    var country: String
    var location: GeoPoint
    var priceLevel: PriceLevel
    var hours: WeeklyHours
    var phone: String?
    var website: String?
    /// Rough currency for prices on this restaurant's menu (ISO 4217).
    var currencyCode: String
    /// Whether the restaurant/brand publishes official nutrition facts.
    var hasOfficialNutrition: Bool
    /// Average health score across the menu, 0–100. Filled in once the menu is
    /// loaded; `nil` until then.
    var averageMenuHealthScore: Double?
    /// Which provider produced this record: used for attribution and merging.
    var providerName: String
    /// Dietary properties the restaurant broadly supports (has vegan options…).
    var dietaryTags: [DietaryTag]
    var photoAssetName: String?

    var primaryCuisine: String { cuisines.first ?? "Restaurant" }

    func isOpen(at date: Date = .now) -> Bool? { hours.isOpen(at: date) }

    func distanceMeters(from origin: GeoPoint?) -> Double? {
        guard let origin else { return nil }
        return location.distance(to: origin)
    }

    /// A loose key for merging duplicate listings from different providers:
    /// normalized name + rounded coordinates.
    var dedupeKey: String {
        let normalizedName = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let lat = (location.latitude * 1000).rounded() / 1000
        let lon = (location.longitude * 1000).rounded() / 1000
        return "\(normalizedName)@\(lat),\(lon)"
    }
}
