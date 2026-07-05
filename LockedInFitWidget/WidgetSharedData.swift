import Foundation
import WidgetKit

/// Snapshot of today's dashboard numbers, mirrored into the App Group so the
/// home screen widget (a separate process) can render without touching
/// HealthKit or SwiftData directly.
///
/// Kept identical to LockedInFit/Support/WidgetSharedData.swift — this target
/// can't share source files with the app target without added project
/// complexity, so the tiny snapshot type is duplicated instead.
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

    static func load() -> WidgetSnapshot? {
        guard let defaults, let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
