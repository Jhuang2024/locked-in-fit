import Foundation
import WidgetKit

/// Snapshot of today's dashboard numbers, mirrored into the App Group so the
/// home screen widget (a separate process) can render without touching
/// HealthKit or SwiftData directly.
struct WidgetSnapshot: Codable, Equatable {
    var score: Int
    var caloriesRemaining: Int
    var calorieTarget: Int
    var steps: Int
    var stepTarget: Int
    var updatedAt: Date
}

enum WidgetSharedData {
    static let appGroupID = "group.com.jerryhuang.LockedInFit"
    private static let key = "widgetSnapshot"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Writes the snapshot and nudges the widget to reload, but only when the
    /// visible numbers actually changed — avoids a pointless reload every time
    /// the 1-second auto-sync loop confirms nothing new arrived.
    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        let changed = load().map { $0.score != snapshot.score
            || $0.caloriesRemaining != snapshot.caloriesRemaining
            || $0.calorieTarget != snapshot.calorieTarget
            || $0.steps != snapshot.steps
            || $0.stepTarget != snapshot.stepTarget
        } ?? true
        defaults.set(data, forKey: key)
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }

    static func load() -> WidgetSnapshot? {
        guard let defaults, let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
