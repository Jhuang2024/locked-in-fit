import Foundation
import SwiftData

/// Aggregated view over the cart's lines: totals, combined scores, warnings, and
/// a per-restaurant grouping. Pure value type so it's trivial to unit-test.
struct CartSummary: Equatable {
    var nutrition: ResolvedNutrition
    var lineCount: Int
    var itemCount: Int
    var combinedHealthScore: Double
    var combinedSatietyScore: Double
    var confidence: NutritionConfidence
    var warnings: [String]

    static let empty = CartSummary(nutrition: .zero, lineCount: 0, itemCount: 0,
                                   combinedHealthScore: 0, combinedSatietyScore: 0,
                                   confidence: .medium, warnings: [])
    var isEmpty: Bool { lineCount == 0 }
}

/// Operations on the persistent meal cart. The set of all `CartLine` rows *is*
/// the cart, so everything here works directly on the `ModelContext`. The cart
/// survives leaving the screen or the app closing, and freely mixes items from
/// multiple restaurants plus ad-hoc custom foods.
enum CartManager {

    // MARK: Building lines

    /// Build a persistent line from a resolved menu item. Caches per-unit macros
    /// and scores for fast totals; stores the full spec for later editing.
    static func makeLine(from resolved: ResolvedMenuItem, restaurantName: String, isCustom: Bool = false) -> CartLine {
        let item = resolved.item
        let line = CartLine(
            restaurantID: item.restaurantID,
            restaurantName: restaurantName,
            itemName: item.name,
            itemDescription: item.itemDescription,
            currencyCode: item.currencyCode,
            price: item.price ?? 0,
            isCustom: isCustom,
            quantity: resolved.config.effectiveQuantity)
        apply(resolved: resolved, to: line)
        return line
    }

    /// Refresh a line's cached values + spec from a (re-)resolved item. Used when
    /// the user edits quantity or modifications from the cart.
    static func apply(resolved: ResolvedMenuItem, to line: CartLine) {
        let n = resolved.perUnit
        line.quantity = resolved.config.effectiveQuantity
        line.unitCalories = n.calories
        line.unitProtein = n.protein
        line.unitCarbs = n.carbs
        line.unitFat = n.fat
        line.unitFiber = n.fiber
        line.unitSodium = n.sodium
        line.unitOilCalories = n.oilCalories
        line.healthScore = resolved.healthScore
        line.satietyScore = resolved.satietyScore
        line.sourceKindRaw = resolved.sourceKind.rawValue
        line.confidenceRaw = resolved.confidence.rawValue
        line.dietaryWarningsRaw = resolved.dietaryWarnings
        line.modificationSummary = modificationSummary(for: resolved)
        line.specData = (try? JSONEncoder().encode(CartItemSpec(item: resolved.item, config: resolved.config, isCustom: line.isCustom))) ?? Data()
    }

    static func modificationSummary(for resolved: ResolvedMenuItem) -> String {
        var parts: [String] = []
        let selected = resolved.item.modifications.filter { resolved.config.selectedModificationIDs.contains($0.id) }
        parts.append(contentsOf: selected.map(\.label))
        if let oil = resolved.config.oilLevelOverride {
            parts.append("\(oil.label) oil")
        }
        if !resolved.config.notes.isEmpty { parts.append(resolved.config.notes) }
        return parts.joined(separator: ", ")
    }

    // MARK: Mutations

    static func add(_ resolved: ResolvedMenuItem, restaurantName: String, context: ModelContext) {
        let line = makeLine(from: resolved, restaurantName: restaurantName)
        context.insert(line)
        try? context.save()
    }

    static func addCustomFood(name: String, nutrition: ResolvedNutrition,
                              healthScore: Double = 0, satietyScore: Double = 0,
                              context: ModelContext) {
        let line = CartLine(restaurantID: "custom", restaurantName: "Custom foods",
                            itemName: name, isCustom: true, quantity: 1)
        line.unitCalories = nutrition.calories
        line.unitProtein = nutrition.protein
        line.unitCarbs = nutrition.carbs
        line.unitFat = nutrition.fat
        line.unitFiber = nutrition.fiber
        line.unitSodium = nutrition.sodium
        line.healthScore = healthScore
        line.satietyScore = satietyScore
        line.sourceKindRaw = NutritionSourceKind.estimatedFromIngredients.rawValue
        line.confidenceRaw = NutritionConfidence.low.rawValue
        context.insert(line)
        try? context.save()
    }

    /// Add a user-described, AI-estimated dish, grouped under its restaurant.
    static func addDescribed(name: String, restaurant: Restaurant, nutrition: ResolvedNutrition,
                             healthScore: Double, satietyScore: Double,
                             confidence: NutritionConfidence, quantity: Int, context: ModelContext) {
        let line = CartLine(restaurantID: restaurant.id, restaurantName: restaurant.name,
                            itemName: name.isEmpty ? "Described dish" : name,
                            currencyCode: restaurant.currencyCode, quantity: max(1, quantity))
        line.unitCalories = nutrition.calories
        line.unitProtein = nutrition.protein
        line.unitCarbs = nutrition.carbs
        line.unitFat = nutrition.fat
        line.unitFiber = nutrition.fiber
        line.unitSodium = nutrition.sodium
        line.healthScore = healthScore
        line.satietyScore = satietyScore
        line.sourceKindRaw = (confidence == .low ? NutritionSourceKind.lowConfidenceEstimate : .estimatedFromIngredients).rawValue
        line.confidenceRaw = confidence.rawValue
        line.modificationSummary = "You described this"
        context.insert(line)
        try? context.save()
    }

    static func setQuantity(_ line: CartLine, to quantity: Int, context: ModelContext) {
        line.quantity = max(1, quantity)
        try? context.save()
    }

    static func duplicate(_ line: CartLine, context: ModelContext) {
        let copy = CartLine(restaurantID: line.restaurantID, restaurantName: line.restaurantName,
                            itemName: line.itemName, itemDescription: line.itemDescription,
                            currencyCode: line.currencyCode, price: line.price,
                            isCustom: line.isCustom, quantity: line.quantity)
        copy.unitCalories = line.unitCalories
        copy.unitProtein = line.unitProtein
        copy.unitCarbs = line.unitCarbs
        copy.unitFat = line.unitFat
        copy.unitFiber = line.unitFiber
        copy.unitSodium = line.unitSodium
        copy.unitOilCalories = line.unitOilCalories
        copy.healthScore = line.healthScore
        copy.satietyScore = line.satietyScore
        copy.sourceKindRaw = line.sourceKindRaw
        copy.confidenceRaw = line.confidenceRaw
        copy.dietaryWarningsRaw = line.dietaryWarningsRaw
        copy.modificationSummary = line.modificationSummary
        copy.specData = line.specData
        context.insert(copy)
        try? context.save()
    }

    static func remove(_ line: CartLine, context: ModelContext) {
        context.delete(line)
        try? context.save()
    }

    static func clear(_ lines: [CartLine], context: ModelContext) {
        for line in lines { context.delete(line) }
        try? context.save()
    }

    // MARK: Totals

    static func summary(for lines: [CartLine]) -> CartSummary {
        guard !lines.isEmpty else { return .empty }
        var total = ResolvedNutrition.zero
        var healthWeighted = 0.0
        var satietyWeighted = 0.0
        var weight = 0.0
        var itemCount = 0
        var minConfidence = NutritionConfidence.high
        var warnings = Set<String>()

        for line in lines {
            let n = line.lineNutrition
            total = total + n
            let w = max(1, n.calories)
            healthWeighted += line.healthScore * w
            satietyWeighted += line.satietyScore * w
            weight += w
            itemCount += max(1, line.quantity)
            minConfidence = NutritionConfidence.min(minConfidence, line.confidence)
            line.dietaryWarningsRaw.forEach { warnings.insert($0) }
        }
        // A combined meal with very high total sodium warns even if no single item did.
        if total.sodium >= 2000 { warnings.insert("Combined sodium is very high: \(Int(total.sodium)) mg") }

        return CartSummary(
            nutrition: total,
            lineCount: lines.count,
            itemCount: itemCount,
            combinedHealthScore: weight > 0 ? (healthWeighted / weight).rounded() : 0,
            combinedSatietyScore: weight > 0 ? (satietyWeighted / weight).rounded() : 0,
            confidence: minConfidence,
            warnings: Array(warnings).sorted())
    }

    /// Group lines by restaurant for the cart's grouped display.
    static func groupedByRestaurant(_ lines: [CartLine]) -> [(name: String, lines: [CartLine])] {
        let groups = Dictionary(grouping: lines) { $0.restaurantName }
        return groups
            .map { (name: $0.key, lines: $0.value.sorted { $0.addedAt < $1.addedAt }) }
            .sorted { $0.name < $1.name }
    }
}
