import Foundation

/// The user's chosen configuration for a menu item: selected modifications,
/// oil override, quantity, and any ad-hoc component edits. Encoded into the
/// persistent cart so an item can be re-opened and re-edited later.
struct ItemConfiguration: Codable, Equatable {
    var selectedModificationIDs: Set<String> = []
    /// User override of the item's oil assumption; `nil` = use the item default.
    var oilLevelOverride: OilLevel? = nil
    /// Explicit grams of oil when `oilLevelOverride == .custom`.
    var customOilGrams: Double? = nil
    /// Number of this item ordered.
    var quantity: Int = 1
    /// Components added by "add protein" / "add ingredient".
    var extraComponents: [MenuItemComponent] = []
    /// Components removed by "remove ingredient".
    var removedComponentIDs: Set<String> = []
    /// Per-component scale from "custom quantity" controls.
    var componentScaleOverrides: [String: Double] = [:]
    var sauceOnSide: Bool = false
    var notes: String = ""

    var effectiveQuantity: Int { max(1, quantity) }
}

/// A transparent record of how an estimate was computed, stored so the user can
/// inspect and correct it. Never thrown away — the detail screen renders this.
struct NutritionEstimateBreakdown: Codable, Equatable {
    struct Line: Codable, Equatable {
        var label: String
        var calories: Double
        var protein: Double
        var fat: Double
        var detail: String
    }
    var componentLines: [Line] = []
    var oilCalories: Double = 0
    var oilFatGrams: Double = 0
    var oilDetail: String = ""
    var portionMultiplier: Double = 1
    var notes: [String] = []
}

/// The fully resolved result of applying a configuration to a menu item for a
/// given user profile: nutrition, scores, breakdown, and warnings. Everything
/// the UI and cart need, in one immutable snapshot.
struct ResolvedMenuItem: Equatable {
    var item: MenuItem
    var config: ItemConfiguration
    /// Rounded, display-ready nutrition for a single unit (respects official vs
    /// estimated rounding rules).
    var perUnit: ResolvedNutrition
    /// perUnit × quantity.
    var total: ResolvedNutrition
    var healthScore: Double
    var satietyScore: Double
    var confidence: NutritionConfidence
    var sourceKind: NutritionSourceKind
    var breakdown: NutritionEstimateBreakdown
    var healthReasons: [String]
    var satietyReasons: [String]
    var dietaryWarnings: [String]

    var quantity: Int { config.effectiveQuantity }
}
