import Foundation

/// One editable line in a spoken/typed meal preview.
struct ParsedMealEntry: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var grams: Double
    var method: CookingMethod
    /// Nutrition for this entry, oil already applied per the oil rules, rounded.
    var nutrition: ResolvedNutrition
    var oilCalories: Double
    /// Flagged when we weren't confident about the interpretation.
    var isUncertain: Bool
    var note: String
}

/// A full parsed meal ready for the user to review, correct, and confirm before
/// logging. Never logged automatically; confirmation is required.
struct ParsedMealPreview: Equatable {
    var entries: [ParsedMealEntry]
    var mealType: MealType
    var total: ResolvedNutrition
    var confidence: NutritionConfidence
    var uncertainTerms: [String]
    var transcript: String
    /// Brands / restaurants mentioned (e.g. "Domino's"), surfaced as context.
    var mentionedBrands: [String]

    var isEmpty: Bool { entries.isEmpty }
}

/// Turns a natural-language meal description ("I ate two scrambled eggs, two
/// pieces of toast with a little butter, and a medium banana") into a structured,
/// editable preview. Shares the exact ingredient/oil model used by Menu Checker,
/// so the steamed/raw = zero-added-oil rule applies identically here.
enum MealSpeechParser {

    static func parse(_ transcript: String, mealTypeHint: MealType? = nil, now: Date = .now) -> ParsedMealPreview {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = IngredientParser.parse(name: text)

        // Global oil instruction ("no oil" / "light oil") applies to the meal.
        let globalOil = parsed.oilLevel

        var entries: [ParsedMealEntry] = []
        var total = ResolvedNutrition.zero
        for pc in parsed.components {
            let level = oilLevel(for: pc, global: globalOil)
            let oil = MenuOilEstimator.estimate(
                foodName: pc.profile.canonicalName, method: pc.method, grams: pc.grams,
                level: level, carriesOwnFat: pc.profile.carriesOwnFat)
            var n = pc.profile.per100g * (pc.grams / 100)
            n.calories += oil.calories
            n.fat += oil.grams
            n.oilCalories = oil.calories
            n.oilFatGrams = oil.grams
            let rounded = MenuValueRounding.round(n)
            entries.append(ParsedMealEntry(
                name: pc.profile.canonicalName,
                grams: pc.grams,
                method: pc.method,
                nutrition: rounded,
                oilCalories: rounded.oilCalories,
                isUncertain: false,
                note: noteFor(method: pc.method, oil: oil)))
            total = total + rounded
        }

        // Surface unparsed descriptive words as uncertain, editable placeholders.
        for term in parsed.uncertainTerms {
            entries.append(ParsedMealEntry(
                name: term.capitalized, grams: 0, method: .unknown,
                nutrition: .zero, oilCalories: 0, isUncertain: true,
                note: "Couldn't estimate: tap to set nutrition"))
        }

        let mealType = mealTypeHint ?? detectMealType(in: text) ?? MealType.guess(for: now)
        return ParsedMealPreview(
            entries: entries,
            mealType: mealType,
            total: total,
            confidence: parsed.confidence,
            uncertainTerms: parsed.uncertainTerms,
            transcript: text,
            mentionedBrands: detectBrands(in: text))
    }

    /// Steamed/raw/boiled components take no oil unless a global "extra oil" was
    /// stated; everything else takes the global level or a per-method default.
    private static func oilLevel(for pc: ParsedComponent, global: OilLevel?) -> OilLevel {
        if pc.method == .steamed || pc.method == .raw { return OilLevel.none }
        if let global { return global }
        if pc.method == .boiled || pc.method == .poached { return OilLevel.none }
        return .standard
    }

    private static func noteFor(method: CookingMethod, oil: OilEstimate) -> String {
        if method == .steamed || method == .raw {
            return "\(method.label): zero added oil"
        }
        if oil.isZero { return method.label }
        return "\(method.label) · +\(Int(oil.calories.rounded())) kcal oil"
    }

    private static func detectMealType(in text: String) -> MealType? {
        let l = text.lowercased()
        if l.contains("breakfast") { return .breakfast }
        if l.contains("lunch") { return .lunch }
        if l.contains("dinner") || l.contains("supper") { return .dinner }
        if l.contains("snack") { return .snack }
        return nil
    }

    /// Detect a "from <Brand>" mention so it can be shown as context.
    private static func detectBrands(in text: String) -> [String] {
        var brands: [String] = []
        let known = ["domino", "mcdonald", "kfc", "subway", "starbucks", "chipotle",
                     "burger king", "wendy", "taco bell", "pizza hut", "nando", "five guys"]
        let l = text.lowercased()
        for brand in known where l.contains(brand) {
            brands.append(brand.prefix(1).uppercased() + brand.dropFirst())
        }
        return brands
    }
}
