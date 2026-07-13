import Foundation
import SwiftData

/// Codable snapshot of a menu item plus its configuration, stored inside a
/// `CartLine` so the item can be re-opened, re-edited, and re-resolved later
/// even if the restaurant menu is no longer loaded.
struct CartItemSpec: Codable, Equatable {
    var item: MenuItem
    var config: ItemConfiguration
    /// A custom (non-restaurant) food the user added alongside menu items.
    var isCustom: Bool = false
}

/// One line in the persistent meal cart. The set of all `CartLine` rows *is* the
/// cart (there is no parent entity), so the cart survives leaving the screen or
/// the app being killed, and can freely mix items from multiple restaurants.
///
/// Cached per-unit macros/scores are denormalized onto the row for fast totals
/// and list rendering; `specData` holds the full spec for editing.
@Model
final class CartLine {
    var id: UUID = UUID()
    var addedAt: Date = Date()
    var restaurantID: String = ""
    var restaurantName: String = ""
    var itemName: String = ""
    var itemDescription: String = ""
    var currencyCode: String = "USD"
    var price: Double = 0
    var isCustom: Bool = false

    var quantity: Int = 1
    // Cached resolved per-unit nutrition (post modifications/oil/portion).
    var unitCalories: Double = 0
    var unitProtein: Double = 0
    var unitCarbs: Double = 0
    var unitFat: Double = 0
    var unitFiber: Double = 0
    var unitSodium: Double = 0
    var unitOilCalories: Double = 0
    var healthScore: Double = 0
    var satietyScore: Double = 0
    var sourceKindRaw: String = NutritionSourceKind.estimatedFromIngredients.rawValue
    var confidenceRaw: String = NutritionConfidence.medium.rawValue
    var dietaryWarningsRaw: [String] = []
    var modificationSummary: String = ""

    /// Encoded `CartItemSpec`.
    var specData: Data = Data()

    init(id: UUID = UUID(),
         addedAt: Date = .now,
         restaurantID: String,
         restaurantName: String,
         itemName: String,
         itemDescription: String = "",
         currencyCode: String = "USD",
         price: Double = 0,
         isCustom: Bool = false,
         quantity: Int = 1) {
        self.id = id
        self.addedAt = addedAt
        self.restaurantID = restaurantID
        self.restaurantName = restaurantName
        self.itemName = itemName
        self.itemDescription = itemDescription
        self.currencyCode = currencyCode
        self.price = price
        self.isCustom = isCustom
        self.quantity = quantity
    }

    var sourceKind: NutritionSourceKind {
        NutritionSourceKind(rawValue: sourceKindRaw) ?? .estimatedFromIngredients
    }
    var confidence: NutritionConfidence {
        NutritionConfidence(rawValue: confidenceRaw) ?? .medium
    }

    /// Total nutrition for this line (per-unit × quantity).
    var lineNutrition: ResolvedNutrition {
        ResolvedNutrition(
            calories: unitCalories, protein: unitProtein, carbs: unitCarbs,
            fat: unitFat, fiber: unitFiber, sodium: unitSodium,
            oilCalories: unitOilCalories, oilFatGrams: 0) * Double(max(1, quantity))
    }

    /// Decode the stored spec for editing; returns nil if the row predates a
    /// schema change or was never populated.
    var spec: CartItemSpec? {
        guard !specData.isEmpty else { return nil }
        return try? JSONDecoder().decode(CartItemSpec.self, from: specData)
    }
}
