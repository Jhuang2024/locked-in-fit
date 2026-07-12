import SwiftUI
import SwiftData

/// Value-based navigation routes for Menu Checker. `NavigationLink(value:)` +
/// a single `navigationDestination(for:)` keeps destinations LAZY: eager
/// `NavigationLink(destination:)` builds every destination view (each with its
/// own @Query set) on every render pass, which on iOS 26 livelocks the main
/// thread in view-list flattening — the same issue SettingsRoute avoids.
enum MenuRoute: Hashable {
    case home
    case menu(Restaurant, GeoPoint?)
    case item(MenuItem, String) // item + restaurant name
}

extension View {
    /// Registers the Menu Checker navigation destinations. Attach at the Log
    /// tab's NavigationStack ROOT (DailyLogView): value-based destinations are
    /// only reliably found when declared on the stack root, so links from any
    /// pushed Menu Checker screen (home, restaurant menu, item detail) resolve.
    /// Destinations are built lazily, only when a route is actually pushed.
    func menuCheckerNavigationDestinations() -> some View {
        navigationDestination(for: MenuRoute.self) { route in
            switch route {
            case .home:
                MenuCheckerHomeView()
            case .menu(let restaurant, let origin):
                RestaurantMenuView(restaurant: restaurant, origin: origin)
            case .item(let item, let restaurantName):
                MenuItemDetailView(item: item, restaurantName: restaurantName)
            }
        }
    }
}

/// Builds a personalized `ScoringProfile` from the user's profile, active goal,
/// and what they've already eaten today, so Menu Checker scores reflect the same
/// remaining-macro picture the dashboard shows.
enum ScoringProfileBuilder {
    static func make(settings: UserSettings?, goal: Goal?, meals: [MealLog],
                     date: Date = .now, restrictions: [DietaryTag] = []) -> ScoringProfile {
        let today = meals.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        let eatenCalories = today.reduce(0) { $0 + $1.consumedCalories }
        let eatenProtein = today.reduce(0) { $0 + $1.protein }
        let remCal = goal.map { max(0, $0.calorieTarget - eatenCalories) }
        let remPro = goal.map { max(0, $0.proteinTarget - eatenProtein) }
        return ScoringProfile(settings: settings, goal: goal,
                              remainingCalories: remCal, remainingProtein: remPro,
                              restrictions: restrictions)
    }
}

extension UserSettings {
    var usesImperial: Bool { units == .imperial }
}

/// Small toggle helper for modification selection with mutually-exclusive groups.
extension ItemConfiguration {
    mutating func toggle(_ mod: MenuModification, in allMods: [MenuModification]) {
        if let group = mod.group {
            // Clear other selections in the same group first.
            let groupIDs = allMods.filter { $0.group == group }.map(\.id)
            let wasSelected = selectedModificationIDs.contains(mod.id)
            groupIDs.forEach { selectedModificationIDs.remove($0) }
            if !wasSelected { selectedModificationIDs.insert(mod.id) }
        } else {
            if selectedModificationIDs.contains(mod.id) {
                selectedModificationIDs.remove(mod.id)
            } else {
                selectedModificationIDs.insert(mod.id)
            }
        }
    }
}
