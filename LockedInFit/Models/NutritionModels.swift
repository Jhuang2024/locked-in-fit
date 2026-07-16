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
    /// The user's own 1–5 star rating of this meal; 0 = not rated yet.
    /// Additive with a default, per the migration policy in LockedInFitApp.
    var rating: Int = 0

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    /// Sorted by `order`: a SwiftData to-many relationship typed as an array
    /// (`[FoodItem]?`) does not actually guarantee stable insertion order
    /// across fetches/saves the way a plain Swift array would: without an
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
    /// The user's own 1–5 star rating of this food; 0 = not rated yet.
    /// Additive with a default, per the migration policy in LockedInFitApp.
    var rating: Int = 0

    var cookingMethod: CookingMethod {
        get { CookingMethod(rawValue: cookingMethodRaw) ?? .unknown }
        set { cookingMethodRaw = newValue.rawValue }
    }

    /// `referenceGrams` when known, otherwise a best-effort parse of a
    /// leading number out of `serving` (e.g. "150 g", written automatically
    /// by `FoodPresetSyncService` before this field existed), so presets
    /// saved by earlier app versions still scale correctly instead of
    /// falling back to unscaled substitution forever. The parse only
    /// accepts the number when it's followed by a mass/volume unit: a
    /// count-style label like "1 meal" or "2 slices" must read as
    /// unknown (0), not as 1 or 2 *grams* — that off-by-a-few-hundred-x
    /// reference would blow up every gram-scaled substitution of the
    /// preset (Menu Checker's saved meals all use "1 meal").
    var effectiveReferenceGrams: Double {
        if referenceGrams > 0 { return referenceGrams }
        guard let parsed = FoodPreset.parseServingLabel(serving), parsed.isMassOrVolume else { return 0 }
        return parsed.value
    }

    /// True when this food is naturally counted in whole pieces or servings
    /// rather than weighed — a hardboiled egg, a popsicle, a saved "1 meal"
    /// preset. Used by the Add Meal amount step to default to "how many?"
    /// instead of asking for a mass the user has no way of knowing.
    /// Two signals, either one suffices:
    /// - the serving label is count-style ("1 meal", "2 slices"): a leading
    ///   number followed by something that isn't a mass/volume unit;
    /// - the name contains a word for a discrete, countable food. Matched
    ///   on whole words so "bar" can't hide inside "barbecue".
    var isCountedInServings: Bool {
        if let parsed = FoodPreset.parseServingLabel(serving), !parsed.isMassOrVolume {
            return true
        }
        let words = name.lowercased().split { !$0.isLetter }
        return words.contains { word in
            if FoodPreset.countableFoodWords.contains(String(word)) { return true }
            // Plurals: "eggs" → "egg", "sandwiches" → "sandwich".
            if word.hasSuffix("es"), FoodPreset.countableFoodWords.contains(String(word.dropLast(2))) { return true }
            if word.hasSuffix("s"), FoodPreset.countableFoodWords.contains(String(word.dropLast())) { return true }
            return false
        }
    }

    /// Splits a serving label like "150 g", "330ml", or "1 meal" into its
    /// leading number and whether the word after it is a mass/volume unit.
    /// Returns nil when the label doesn't start with a number, or when
    /// nothing follows the number (a bare "2" says nothing either way).
    private static func parseServingLabel(_ serving: String) -> (value: Double, isMassOrVolume: Bool)? {
        let trimmed = serving.trimmingCharacters(in: .whitespaces).lowercased()
        let digits = trimmed.prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let value = Double(digits) else { return nil }
        let rest = trimmed.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        let unit = rest.prefix { $0.isLetter }
        guard !unit.isEmpty else { return nil }
        let massOrVolumeUnits: Set<Substring> =
            ["g", "gram", "grams", "ml", "milliliter", "milliliters", "millilitre", "millilitres"]
        return (value, massOrVolumeUnits.contains(unit))
    }

    /// Discrete foods people count instead of weigh. Deliberately biased
    /// toward things with a well-defined "one": produce sold by the piece,
    /// baked goods, and hand-held items. Bulk foods (rice, noodles,
    /// vegetables, meat by the cut) stay gram-first.
    static let countableFoodWords: Set<String> = [
        "egg", "popsicle", "slice", "sandwich", "burger", "wrap", "cookie",
        "muffin", "donut", "doughnut", "pancake", "waffle", "taco", "burrito",
        "dumpling", "nugget", "meatball", "sausage", "hotdog", "cutlet",
        "patty", "drumstick", "wing", "skewer", "roll", "bun", "tortilla",
        "biscuit", "cracker", "scoop", "bar", "cupcake", "brownie",
        "croissant", "bagel", "pretzel", "banana", "apple", "orange", "pear",
        "peach", "plum", "kiwi", "mandarin", "clementine", "avocado",
    ]

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
