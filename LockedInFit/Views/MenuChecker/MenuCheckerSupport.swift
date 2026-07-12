import SwiftUI
import SwiftData

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
