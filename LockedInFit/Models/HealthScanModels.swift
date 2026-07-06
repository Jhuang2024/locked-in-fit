import Foundation
import SwiftData

/// A one-off scan of a packaged food/product's label — a lookup, not a meal log.
/// Saving one never contributes to daily calorie/macro totals.
@Model
final class HealthScan {
    var date: Date = Date()
    var productName: String = ""
    var photoPath: String?
    var servingSize: String = ""
    /// 0–100, 100 = healthiest.
    var healthScore: Double = 0
    /// 0–100, 100 = extremely filling for its calorie cost.
    var satietyScore: Double = 0
    var processedLevelRaw: String = ProcessedLevel.unknown.rawValue
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sugar: Double = 0
    var sodium: Double = 0
    var confidence: Double = 1.0
    var concerningIngredientsRaw: [String] = []
    var notes: String = ""

    var processedLevel: ProcessedLevel {
        get { ProcessedLevel(rawValue: processedLevelRaw) ?? .unknown }
        set { processedLevelRaw = newValue.rawValue }
    }
    var concerningIngredients: [String] {
        get { concerningIngredientsRaw }
        set { concerningIngredientsRaw = newValue }
    }

    /// Grams of protein per 100 kcal — a quick read on how "worth it" the calories are.
    var proteinPer100kcal: Double {
        guard calories > 0 else { return 0 }
        return (protein / calories) * 100
    }

    init(date: Date = .now,
         productName: String = "",
         photoPath: String? = nil,
         servingSize: String = "",
         healthScore: Double = 0,
         satietyScore: Double = 0,
         processedLevel: ProcessedLevel = .unknown,
         calories: Double = 0,
         protein: Double = 0,
         carbs: Double = 0,
         fat: Double = 0,
         fiber: Double = 0,
         sugar: Double = 0,
         sodium: Double = 0,
         confidence: Double = 1.0,
         concerningIngredients: [String] = [],
         notes: String = "") {
        self.date = date
        self.productName = productName
        self.photoPath = photoPath
        self.servingSize = servingSize
        self.healthScore = healthScore
        self.satietyScore = satietyScore
        self.processedLevelRaw = processedLevel.rawValue
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
        self.confidence = confidence
        self.concerningIngredientsRaw = concerningIngredients
        self.notes = notes
    }
}
