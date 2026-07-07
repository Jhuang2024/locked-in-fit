import Foundation
import SwiftData

@Model
final class MealLog {
    var date: Date = Date()
    var mealTypeRaw: String = MealType.snack.rawValue
    var photoPath: String?
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sodium: Double = 0
    var confidence: Double = 1.0
    var calorieLow: Double = 0
    var calorieHigh: Double = 0
    var hiddenOilLow: Double = 0
    var hiddenOilHigh: Double = 0
    var notes: String = ""
    @Relationship(deleteRule: .cascade) var foodItems: [FoodItem]? = []

    /// 0–100, 100 = healthiest. Only meaningful when analysisState is .completed.
    var healthScore: Double = 0
    /// 0–100, 100 = most filling for its calorie cost.
    var satietyScore: Double = 0
    var factsRaw: [String] = []
    var concernsRaw: [String] = []
    var analysisSummary: String = ""
    /// Missing on entries logged before this feature existed; defaults to
    /// .notAnalyzed so old rows just show "Not analyzed" instead of crashing.
    var analysisStateRaw: String = MealAnalysisState.notAnalyzed.rawValue

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var items: [FoodItem] { foodItems ?? [] }

    var facts: [String] {
        get { factsRaw }
        set { factsRaw = newValue }
    }
    var concerns: [String] {
        get { concernsRaw }
        set { concernsRaw = newValue }
    }
    var analysisState: MealAnalysisState {
        get { MealAnalysisState(rawValue: analysisStateRaw) ?? .notAnalyzed }
        set { analysisStateRaw = newValue.rawValue }
    }
    var isAnalyzed: Bool { analysisState == .completed }

    /// Midpoint of the hidden-oil range; the single value calorie math applies.
    var hiddenOilCalories: Double { (hiddenOilLow + hiddenOilHigh) / 2 }
    /// Calories this meal counts for: logged calories plus hidden oil.
    var consumedCalories: Double { calories + hiddenOilCalories }

    /// "Estimated 620 kcal, likely range 520–820, oil uncertainty +80 to +260."
    var honestSummary: String {
        var text = "Estimated \(Int(calories)) kcal"
        if calorieHigh > calorieLow, calorieHigh > 0 {
            text += ", likely range \(Int(calorieLow))–\(Int(calorieHigh))"
        }
        if hiddenOilHigh > 0 {
            text += ", oil uncertainty +\(Int(hiddenOilLow)) to +\(Int(hiddenOilHigh))"
        }
        return text
    }

    init(date: Date = .now,
         mealType: MealType = .snack,
         photoPath: String? = nil,
         calories: Double = 0,
         protein: Double = 0,
         carbs: Double = 0,
         fat: Double = 0,
         fiber: Double = 0,
         sodium: Double = 0,
         confidence: Double = 1.0,
         calorieLow: Double = 0,
         calorieHigh: Double = 0,
         hiddenOilLow: Double = 0,
         hiddenOilHigh: Double = 0,
         notes: String = "",
         foodItems: [FoodItem] = [],
         healthScore: Double = 0,
         satietyScore: Double = 0,
         facts: [String] = [],
         concerns: [String] = [],
         analysisSummary: String = "",
         analysisState: MealAnalysisState = .notAnalyzed) {
        self.date = date
        self.mealTypeRaw = mealType.rawValue
        self.photoPath = photoPath
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sodium = sodium
        self.confidence = confidence
        self.calorieLow = calorieLow
        self.calorieHigh = calorieHigh
        self.hiddenOilLow = hiddenOilLow
        self.hiddenOilHigh = hiddenOilHigh
        self.notes = notes
        self.foodItems = foodItems
        self.healthScore = healthScore
        self.satietyScore = satietyScore
        self.factsRaw = facts
        self.concernsRaw = concerns
        self.analysisSummary = analysisSummary
        self.analysisStateRaw = analysisState.rawValue
    }
}

@Model
final class FoodItem {
    var name: String = ""
    var grams: Double = 0
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sodium: Double = 0
    var cookingMethodRaw: String = CookingMethod.unknown.rawValue
    var confidence: Double = 1.0
    var meal: MealLog?

    var cookingMethod: CookingMethod {
        get { CookingMethod(rawValue: cookingMethodRaw) ?? .unknown }
        set { cookingMethodRaw = newValue.rawValue }
    }

    init(name: String,
         grams: Double = 0,
         calories: Double = 0,
         protein: Double = 0,
         carbs: Double = 0,
         fat: Double = 0,
         fiber: Double = 0,
         sodium: Double = 0,
         cookingMethod: CookingMethod = .unknown,
         confidence: Double = 1.0) {
        self.name = name
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sodium = sodium
        self.cookingMethodRaw = cookingMethod.rawValue
        self.confidence = confidence
    }
}

@Model
final class FoodPreset {
    var name: String = ""
    var serving: String = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sodium: Double = 0
    var category: String = "General"
    var notes: String = ""
    var cookingMethodRaw: String = CookingMethod.unknown.rawValue

    var cookingMethod: CookingMethod {
        get { CookingMethod(rawValue: cookingMethodRaw) ?? .unknown }
        set { cookingMethodRaw = newValue.rawValue }
    }

    init(name: String,
         serving: String,
         calories: Double,
         protein: Double,
         carbs: Double,
         fat: Double,
         fiber: Double = 0,
         sodium: Double = 0,
         category: String = "General",
         notes: String = "",
         cookingMethod: CookingMethod = .unknown) {
        self.name = name
        self.serving = serving
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sodium = sodium
        self.category = category
        self.notes = notes
        self.cookingMethodRaw = cookingMethod.rawValue
    }
}
