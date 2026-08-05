import Foundation

/// What the user said they ate of a preset: the grams to record on the
/// FoodItem (0 when unknowable, e.g. servings of a preset with no saved
/// weight) and the factor to scale the preset's saved nutrition by. The two
/// are computed together so they always describe the same amount of food.
struct PresetPortion {
    var grams: Double
    var ratio: Double
    /// True when the user said the gram amount came off a scale, exempting
    /// the item from the portion-underestimation uplift.
    var weighed: Bool = false
    /// How many servings the user asked for, when they answered in servings
    /// rather than grams; nil means they answered in grams. Display and
    /// re-editing only: the nutrition math runs off `ratio` either way, but
    /// without this a "2 servings" answer would come back as a bare gram
    /// weight the next time the amount is opened.
    var servings: Double?
}

/// One staged food in the Add Meal preset cart: a preset plus the portion the
/// user entered for it. A value type held in the picker's `@State`, never
/// persisted: this cart is a staging area for the meal being written, not the
/// standalone, app-lifetime cart Menu Checker keeps in `CartLine`. It empties
/// into the meal's Foods section the moment the user taps Add.
struct PresetCartLine: Identifiable {
    let id: UUID
    var preset: FoodPreset
    var portion: PresetPortion

    init(id: UUID = UUID(), preset: FoodPreset, portion: PresetPortion) {
        self.id = id
        self.preset = preset
        self.portion = portion
    }

    var name: String { preset.name }
    var grams: Double { portion.grams }
    var calories: Double { preset.calories * portion.ratio }
    var protein: Double { preset.protein * portion.ratio }
    var carbs: Double { preset.carbs * portion.ratio }
    var fat: Double { preset.fat * portion.ratio }
    var fiber: Double { preset.fiber * portion.ratio }
    var sodium: Double { preset.sodium * portion.ratio }

    /// How much of this food, phrased the way the user entered it: "180 g"
    /// for a weighed amount, "2 × 1 bowl" for a serving count (with the
    /// preset's own serving label when it has one). A serving count that
    /// resolves to a known weight appends it, so a cart row can be checked
    /// against a scale without reopening the amount sheet.
    var amountDescription: String {
        guard let servings = portion.servings else {
            return portion.grams > 0 ? Formatters.grams(portion.grams) : "as saved"
        }
        let label = preset.serving.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = "\(Formatters.trimmed(servings)) × \(label.isEmpty ? "serving" : label)"
        // The total weight is worth appending only when it says something the
        // serving label doesn't. A preset whose weight was parsed back out of
        // a label like "150 g" would just repeat itself; one carrying its own
        // Weight field ("1 bowl", 250 g) turns the count into a number that
        // can be checked against a scale.
        guard portion.grams > 0, preset.referenceGrams > 0 else { return count }
        return "\(count) · \(Formatters.grams(portion.grams))"
    }

    /// The FoodItem this staged line becomes once the cart is added to the meal.
    ///
    /// The portion comes from the user (entered right after picking, in
    /// PresetAmountEntryView — grams for weighed foods, a serving count for
    /// countable ones), never from a preset default. grams and the scaled
    /// nutrition are computed together so they describe the same amount of
    /// food from the moment the item is created: FoodItemEditorRow scales
    /// proportionally from whatever pair it starts with, so a mismatched
    /// starting pair would throw every later edit off by that same wrong
    /// ratio.
    func makeFoodItem(order: Int) -> FoodItem {
        FoodItem(name: preset.name, grams: portion.grams,
                 calories: calories, protein: protein, carbs: carbs, fat: fat,
                 fiber: fiber, sodium: sodium,
                 cookingMethod: preset.cookingMethod, order: order,
                 fromPreset: true, weighed: portion.weighed)
    }
}

/// Running totals for a preset cart, shown live while foods are being added
/// so the user can see the meal add up instead of finding out after saving.
struct PresetCartTotals: Equatable {
    var itemCount: Int = 0
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sodium: Double = 0
}

enum PresetCartMath {
    static func totals(for lines: [PresetCartLine]) -> PresetCartTotals {
        var totals = PresetCartTotals()
        totals.itemCount = lines.count
        for line in lines {
            totals.calories += line.calories
            totals.protein += line.protein
            totals.carbs += line.carbs
            totals.fat += line.fat
            totals.fiber += line.fiber
            totals.sodium += line.sodium
        }
        return totals
    }

    /// The FoodItems a whole cart becomes, ordered after whatever the meal
    /// already holds so an earlier photo/speech/manual pass isn't reshuffled.
    static func foodItems(for lines: [PresetCartLine], startingAt baseOrder: Int) -> [FoodItem] {
        lines.enumerated().map { index, line in line.makeFoodItem(order: baseOrder + index) }
    }
}
