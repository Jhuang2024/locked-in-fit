import Foundation
import SwiftData

/// Manages the user's saved/recent restaurant and item records, keeping the
/// recent list trimmed to a small rolling window.
enum MenuCheckerLibrary {
    static let recentLimit = 12

    static func recordRecent(_ restaurant: Restaurant, context: ModelContext) {
        let descriptor = FetchDescriptor<RecentRestaurantRecord>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)])
        let existing = (try? context.fetch(descriptor)) ?? []
        // Loop breaker: if this restaurant is already the most-recent entry, do
        // NOTHING. `recordRecent` is called from RestaurantMenuView.onAppear, and
        // it mutates the store (delete/insert/save) which invalidates the home
        // view's @Query recents. Re-recording on every appear/re-render fed a
        // navigation update loop that froze the main thread. Writing only on an
        // actual change breaks that cycle.
        guard existing.first?.restaurantID != restaurant.id else { return }
        // Move-to-front: drop any prior record for this restaurant.
        for record in existing where record.restaurantID == restaurant.id {
            context.delete(record)
        }
        context.insert(RecentRestaurantRecord(restaurant: restaurant))
        // Trim overflow.
        let remaining = existing.filter { $0.restaurantID != restaurant.id }
        if remaining.count + 1 > recentLimit {
            for record in remaining.dropFirst(recentLimit - 1) {
                context.delete(record)
            }
        }
        try? context.save()
    }
}
