import Foundation

/// One candidate set of nutrition for an item, from some provider.
struct NutritionCandidate {
    var sourceKind: NutritionSourceKind
    var providerName: String
    var nutrition: ResolvedNutrition?
    var components: [MenuItemComponent]
    var confidence: NutritionConfidence
}

/// Chooses the best available nutrition source for an item. Because restaurant
/// search, menu data, and official nutrition can each come from different
/// providers, an item may arrive with several candidate sources; this picks the
/// most trustworthy without ever upgrading an estimate to "official".
enum NutritionSourceSelector {
    /// Preference order: official → restaurant-provided ingredients → estimated
    /// → low-confidence estimate. Ties break toward higher confidence.
    static func select(from candidates: [NutritionCandidate]) -> NutritionCandidate? {
        guard !candidates.isEmpty else { return nil }
        func rank(_ k: NutritionSourceKind) -> Int {
            switch k {
            case .official: return 3
            case .restaurantProvided: return 2
            case .estimatedFromIngredients: return 1
            case .lowConfidenceEstimate: return 0
            }
        }
        return candidates.max { a, b in
            if rank(a.sourceKind) != rank(b.sourceKind) { return rank(a.sourceKind) < rank(b.sourceKind) }
            return a.confidence.scalar < b.confidence.scalar
        }
    }

    /// Apply the selected candidate onto a menu item, filling in components /
    /// official nutrition / source / confidence. Official candidates set
    /// `officialNutrition` (used verbatim); estimates set decomposed components.
    static func apply(_ candidate: NutritionCandidate, to item: inout MenuItem) {
        item.sourceKind = candidate.sourceKind
        item.baseConfidence = candidate.confidence
        if candidate.sourceKind == .official, let n = candidate.nutrition {
            item.officialNutrition = n
            if !candidate.components.isEmpty { item.components = candidate.components }
        } else {
            item.officialNutrition = nil
            if !candidate.components.isEmpty { item.components = candidate.components }
        }
    }
}
