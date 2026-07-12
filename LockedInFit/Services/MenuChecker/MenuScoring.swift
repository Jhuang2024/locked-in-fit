import Foundation

/// User context used to personalize Health/Satiety scores. Built from the
/// existing profile + active goal + (optionally) the day's remaining macros, so
/// Menu Checker scores reflect the same targets the rest of the app uses.
struct ScoringProfile: Equatable {
    var calorieTarget: Double?
    var proteinTarget: Double?
    var remainingCalories: Double?
    var remainingProtein: Double?
    var goalPhase: GoalPhase?
    var restrictions: [DietaryTag]
    var sodiumLimit: Double

    static let neutral = ScoringProfile(calorieTarget: nil, proteinTarget: nil,
                                        remainingCalories: nil, remainingProtein: nil,
                                        goalPhase: nil, restrictions: [], sodiumLimit: 2300)

    init(calorieTarget: Double?, proteinTarget: Double?,
         remainingCalories: Double?, remainingProtein: Double?,
         goalPhase: GoalPhase?, restrictions: [DietaryTag], sodiumLimit: Double) {
        self.calorieTarget = calorieTarget
        self.proteinTarget = proteinTarget
        self.remainingCalories = remainingCalories
        self.remainingProtein = remainingProtein
        self.goalPhase = goalPhase
        self.restrictions = restrictions
        self.sodiumLimit = sodiumLimit
    }

    init(settings: UserSettings?, goal: Goal?,
         remainingCalories: Double? = nil, remainingProtein: Double? = nil,
         restrictions: [DietaryTag] = []) {
        self.calorieTarget = goal?.calorieTarget
        self.proteinTarget = goal?.proteinTarget
        self.remainingCalories = remainingCalories
        self.remainingProtein = remainingProtein
        self.goalPhase = goal?.phase
        self.restrictions = restrictions
        self.sodiumLimit = settings?.sodiumLimitMg ?? 2300
    }
}

/// Shared derived densities so Health and Satiety scoring read from the same
/// component analysis instead of recomputing it two ways.
struct NutritionSignals {
    var calories: Double
    var proteinPer100kcal: Double
    var fiberPer100kcal: Double
    var sodiumPer100kcal: Double
    var caloriesPerGram: Double
    var vegFraction: Double      // 0–1 of grams from vegetables/salad
    var liquidFraction: Double   // 0–1 of calories from drinks
    var addedSugarCalories: Double
    var ownFatCalories: Double   // cheese/butter/sauces/fried fat calories
    var deepFried: Bool
    var totalGrams: Double

    init(nutrition: ResolvedNutrition, components: [MenuItemComponent]) {
        calories = max(1, nutrition.calories)
        proteinPer100kcal = nutrition.protein / calories * 100
        fiberPer100kcal = nutrition.fiber / calories * 100
        sodiumPer100kcal = nutrition.sodium / calories * 100
        totalGrams = max(1, components.reduce(0) { $0 + $1.grams })
        caloriesPerGram = nutrition.calories / totalGrams

        let vegGrams = components.filter { $0.kind == .vegetable }.reduce(0) { $0 + $1.grams }
        vegFraction = min(1, vegGrams / totalGrams)

        let drinkCals = components.filter { $0.kind == .drinkBase }.reduce(0) { $0 + $1.base.calories }
        liquidFraction = min(1, drinkCals / calories)

        addedSugarCalories = components.filter { $0.kind == .sweetener || ($0.kind == .drinkBase && $0.base.calories > 40) }
            .reduce(0) { $0 + $1.base.carbs * 4 }
        ownFatCalories = components.filter { $0.kind == .cheese || $0.kind == .sauce || $0.kind == .dressing }
            .reduce(0) { $0 + $1.base.fat * 9 }
        deepFried = components.contains { $0.cookingMethod == .deepFried || $0.cookingMethod == .restaurantHighOil }
    }
}

/// Personalized Health Score, 0–100. Not a "low-calorie = healthy" calculator:
/// a large, balanced, high-protein meal can score well, and a small sugary item
/// can score poorly. Considers protein/fibre density, veg content, processing,
/// added sugar, saturated fat, sodium, calorie density, and goal fit.
enum MenuHealthScoreCalculator {
    static func score(nutrition: ResolvedNutrition,
                      components: [MenuItemComponent],
                      sourceKind: NutritionSourceKind,
                      profile: ScoringProfile = .neutral) -> (score: Double, reasons: [String]) {
        let s = NutritionSignals(nutrition: nutrition, components: components)
        var score = 50.0
        var reasons: [String] = []

        // Protein density.
        let proteinBonus = min(18, s.proteinPer100kcal * 2.4)
        score += proteinBonus
        if s.proteinPer100kcal >= 7 { reasons.append("High protein for its calories") }
        else if s.proteinPer100kcal < 2.5 && s.calories > 150 { reasons.append("Low protein for its calorie count") }

        // Fibre.
        score += min(14, s.fiberPer100kcal * 6)
        if s.fiberPer100kcal >= 2.5 { reasons.append("Good source of fibre") }

        // Vegetables / whole foods.
        score += min(10, s.vegFraction * 22)
        if s.vegFraction >= 0.3 { reasons.append("Plenty of vegetables") }

        // Processing / deep-frying.
        if s.deepFried { score -= 9; reasons.append("Deep-fried") }
        if sourceKind == .lowConfidenceEstimate { score -= 3 }

        // Added sugar.
        if s.addedSugarCalories > 60 {
            score -= min(14, s.addedSugarCalories / 15)
            reasons.append("High in added sugar")
        }

        // Saturated / heavy fat from cheese, butter, creamy sauces.
        if s.ownFatCalories > s.calories * 0.35 {
            score -= 8
            reasons.append("Rich in saturated fat")
        }

        // Sodium.
        let sodiumPenalty = min(18, max(0, (s.sodiumPer100kcal - 120) / 9))
        score -= sodiumPenalty
        if s.sodiumPer100kcal >= 200 { reasons.append("Very high in sodium") }
        else if s.sodiumPer100kcal >= 150 { reasons.append("High in sodium") }

        // Calorie density — gentle, not dominant.
        if s.caloriesPerGram > 3.2 { score -= 5 }
        else if s.caloriesPerGram < 1.2 && s.calories > 120 { score += 3 }

        // Liquid calories are a weaker form of nutrition when they dominate.
        if s.liquidFraction > 0.7 && s.proteinPer100kcal < 3 { score -= 6; reasons.append("Mostly liquid calories") }

        // Goal personalization.
        score += goalAdjustment(signals: s, nutrition: nutrition, profile: profile, reasons: &reasons)

        // Balanced-but-dense recognition: high protein + fibre earns a floor even
        // when calorie-dense, so we don't punish a genuinely good big meal.
        if s.proteinPer100kcal >= 6 && s.fiberPer100kcal >= 1.5 && score < 62 {
            score = 62
            if !reasons.contains(where: { $0.contains("balanced") }) {
                reasons.append("Calorie-dense but nutritionally balanced")
            }
        }

        // Dietary-restriction conflicts.
        for restriction in profile.restrictions {
            if conflicts(components: components, restriction: restriction) {
                score -= 6
                reasons.append("May not fit your \(restriction.label.lowercased()) preference")
            }
        }

        score = min(100, max(5, score.rounded()))
        return (score, dedupeReasons(reasons))
    }

    private static func goalAdjustment(signals s: NutritionSignals,
                                       nutrition: ResolvedNutrition,
                                       profile: ScoringProfile,
                                       reasons: inout [String]) -> Double {
        var adj = 0.0
        // Fits today's remaining macros: protein-forward and within calorie room.
        if let remCal = profile.remainingCalories, let remPro = profile.remainingProtein {
            if nutrition.calories <= max(0, remCal) && nutrition.protein >= remPro * 0.35 && remPro > 0 {
                adj += 6
                reasons.append("Strong fit for today's remaining macros")
            } else if remCal > 0 && nutrition.calories > remCal * 1.15 {
                adj -= 4
                reasons.append("More calories than you have left today")
            }
        }
        switch profile.goalPhase {
        case .cut:
            // On a cut, reward protein-per-calorie; only mildly penalize density
            // when protein is also poor (so a lean big salad isn't punished).
            if s.proteinPer100kcal >= 6 { adj += 3 }
            if s.caloriesPerGram > 2.8 && s.proteinPer100kcal < 4 { adj -= 4 }
        case .leanBulk, .aggressiveBulk:
            // On a bulk, calorie-dense protein is useful, not bad.
            if s.proteinPer100kcal >= 5 && nutrition.calories >= 500 { adj += 3 }
        default:
            break
        }
        return adj
    }

    private static func conflicts(components: [MenuItemComponent], restriction: DietaryTag) -> Bool {
        let profilesByName = Dictionary(FoodNutritionTable.all.map { ($0.canonicalName, $0) }, uniquingKeysWith: { a, _ in a })
        switch restriction {
        case .vegetarian, .vegan:
            return components.contains { c in
                let tags = profilesByName[c.name]?.dietaryTags ?? []
                return !(tags.contains(restriction))
            }
        default:
            return false
        }
    }

    private static func dedupeReasons(_ reasons: [String]) -> [String] {
        var seen = Set<String>()
        return reasons.filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }
}

/// Satiety Score, 0–100: how filling an item is *relative to its calories*, not
/// how physically large it is. Built from protein, fibre, food volume, water
/// content, calorie density, solid-vs-liquid calories, fat, and refined carbs.
enum SatietyScoreCalculator {
    static func score(nutrition: ResolvedNutrition,
                      components: [MenuItemComponent],
                      profile: ScoringProfile = .neutral) -> (score: Double, reasons: [String]) {
        let s = NutritionSignals(nutrition: nutrition, components: components)
        var score = 40.0
        var reasons: [String] = []

        // Protein is the strongest satiety driver.
        let proteinBonus = min(28, s.proteinPer100kcal * 3.6)
        score += proteinBonus
        if s.proteinPer100kcal >= 7 { reasons.append("High protein") }

        // Fibre.
        score += min(18, s.fiberPer100kcal * 7)
        if s.fiberPer100kcal >= 2.5 { reasons.append("High fibre") }
        else if s.fiberPer100kcal < 0.6 && s.calories > 150 { reasons.append("Low fibre") }

        // Food volume: lower calorie density = more food per calorie = fuller.
        if s.caloriesPerGram < 1.0 { score += 18; reasons.append("Large, low-density portion") }
        else if s.caloriesPerGram < 1.6 { score += 12; reasons.append("Good food volume") }
        else if s.caloriesPerGram > 3.2 { score -= 10; reasons.append("Calorie-dense with a small serving") }

        // Water content from vegetables / soups.
        score += min(8, s.vegFraction * 16)

        // Liquid calories empty out fast.
        if s.liquidFraction > 0.6 {
            score -= min(25, s.liquidFraction * 30)
            reasons.append("Mostly liquid calories")
        }

        // Refined carbs / added sugar digest quickly.
        if s.addedSugarCalories > 60 { score -= 8 }

        // Some fat slows digestion, but fat-dominant + low protein doesn't fill.
        let fatCals = nutrition.fat * 9
        if fatCals > s.calories * 0.55 && s.proteinPer100kcal < 3 { score -= 6 }

        // Big, protein- and fibre-rich meals keep you full for hours.
        if nutrition.calories >= 450 && s.proteinPer100kcal >= 6 && s.fiberPer100kcal >= 1.5 {
            score += 4
            reasons.append("Likely to keep you full for several hours")
        }

        score = min(100, max(5, score.rounded()))
        var seen = Set<String>()
        let deduped = reasons.filter { seen.insert($0).inserted }.prefix(4).map { $0 }
        return (score, deduped)
    }
}
