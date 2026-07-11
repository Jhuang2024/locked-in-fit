import Foundation
import SwiftData

@Model
final class MealLog {
    var date: Date = Date()
    var mealTypeRaw: String = MealType.snack.rawValue
    var photoPath: String?
    /// Additional photos beyond `photoPath`, for meals logged from several
    /// pictures (multiple dishes, or the same spread from different angles).
    /// `photoPath` stays the primary/thumbnail photo so every existing view
    /// keeps working; these are the rest, in the order they were added.
    /// Additive with a default, per the migration policy in LockedInFitApp.
    var extraPhotoPaths: [String] = []
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

    /// Sorted by `order`: a SwiftData to-many relationship typed as an array
    /// (`[FoodItem]?`) does not actually guarantee stable insertion order
    /// across fetches/saves the way a plain Swift array would — without an
    /// explicit order field, items can silently reshuffle after a save and
    /// reload. Same fix already applied to Exercise/WorkoutSet; FoodItem
    /// never got it.
    var items: [FoodItem] { (foodItems ?? []).sorted { $0.order < $1.order } }

    /// Every photo attached to this meal (primary first), for display and
    /// for cleanup on delete. Same shape as AppearanceCheckIn.allPhotoPaths.
    var allPhotoPaths: [String?] { [photoPath] + extraPhotoPaths.map(Optional.some) }

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
    /// Calories from preset (known, pre-measured) items in this meal. Excluded
    /// from the portion-underestimation uplift.
    var presetCalories: Double { (foodItems ?? []).filter { $0.fromPreset }.reduce(0) { $0 + $1.calories } }

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
    /// Position within the meal's food list; see MealLog.items.
    var order: Int = 0
    /// True when this item's numbers came from a saved preset (a known,
    /// pre-measured food) rather than an eyeballed/AI estimate. Preset calories
    /// are excluded from the portion-underestimation uplift, since there's no
    /// portion to underestimate.
    var fromPreset: Bool = false

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
         confidence: Double = 1.0,
         order: Int = 0,
         fromPreset: Bool = false) {
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
        self.order = order
        self.fromPreset = fromPreset
    }
}

@Model
final class FoodPreset {
    var name: String = ""
    var serving: String = ""
    /// The weight, in grams, that `calories`/`protein`/`carbs`/`fat`/`fiber`/
    /// `sodium` below actually correspond to. Required to scale this
    /// preset's saved numbers to whatever portion a new meal actually logs
    /// (see `effectiveReferenceGrams` and `MealEstimate.FoodItemEstimate.makeFoodItem`);
    /// without it, applying a preset to a differently-sized portion silently
    /// pairs the wrong calorie total with the new gram amount. Presets saved
    /// before this field existed default to 0 (unknown).
    var referenceGrams: Double = 0
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

    /// `referenceGrams` when known, otherwise a best-effort parse of a
    /// leading number out of `serving` (e.g. "150 g", written automatically
    /// by `FoodPresetSyncService` before this field existed) — so presets
    /// saved by earlier app versions still scale correctly instead of
    /// falling back to unscaled substitution forever.
    var effectiveReferenceGrams: Double {
        if referenceGrams > 0 { return referenceGrams }
        let digits = serving.prefix { $0.isNumber || $0 == "." }
        return Double(digits) ?? 0
    }

    init(name: String,
         serving: String,
         referenceGrams: Double = 0,
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
        self.referenceGrams = referenceGrams
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
