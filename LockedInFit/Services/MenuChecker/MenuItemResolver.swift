import Foundation

/// Applies an `ItemConfiguration` (modifications, oil, portion, quantity) to a
/// `MenuItem` for a given `ScoringProfile` and produces a fully `ResolvedMenuItem`:
/// nutrition, Health/Satiety scores, a transparent breakdown, and warnings.
///
/// Two nutrition paths, chosen by source:
/// - **Official**: the restaurant's published macros are used verbatim. We never
///   add our own cooking-oil estimate on top (that would double-count), and the
///   numbers are shown exactly, not re-rounded. Modifications only add/subtract
///   their own explicit component macros.
/// - **Estimated**: macros are summed from components, then added cooking oil is
///   estimated per component (steamed/raw = exactly zero), then rounded so we
///   never show fake precision.
enum MenuItemResolver {

    static func resolve(item: MenuItem,
                        config: ItemConfiguration = ItemConfiguration(),
                        profile: ScoringProfile = .neutral) -> ResolvedMenuItem {
        let effective = effectiveComponents(item: item, config: config)
        let components = effective.components
        let oilLevel = effective.oilLevel
        let portion = effective.portionMultiplier

        var breakdown = NutritionEstimateBreakdown()
        breakdown.portionMultiplier = portion

        let usesOfficial = item.sourceKind == .official && item.officialNutrition != nil

        var raw: ResolvedNutrition
        if usesOfficial {
            raw = officialNutrition(item: item, config: config, components: components, breakdown: &breakdown)
        } else {
            raw = estimatedNutrition(components: components, oilLevel: oilLevel,
                                     customOilGrams: config.customOilGrams, breakdown: &breakdown)
        }
        // Whole-dish portion scaling applies last, to everything.
        if portion != 1 {
            raw = raw * portion
            breakdown.notes.append("Portion ×\(Formatters.trimmed(portion))")
        }

        // Rounding: never re-round official numbers' calories; estimates round to
        // avoid fake precision.
        let roundCalories = !usesOfficial
        let perUnit = MenuValueRounding.round(raw, roundCalories: roundCalories)
        let total = perUnit * Double(config.effectiveQuantity)

        // Scoring runs on the single-unit resolved nutrition + effective
        // components, so it recalculates whenever quantity/mods/oil change.
        let scoringComponents = components.isEmpty ? syntheticComponents(from: perUnit) : components
        let health = MenuHealthScoreCalculator.score(nutrition: perUnit, components: scoringComponents,
                                                     sourceKind: item.sourceKind, profile: profile)
        let satiety = SatietyScoreCalculator.score(nutrition: perUnit, components: scoringComponents, profile: profile)

        let confidence = resolvedConfidence(item: item, config: config, usesOfficial: usesOfficial)
        let warnings = dietaryWarnings(item: item, nutrition: perUnit, components: components, profile: profile)

        return ResolvedMenuItem(
            item: item, config: config,
            perUnit: perUnit, total: total,
            healthScore: health.score, satietyScore: satiety.score,
            confidence: confidence, sourceKind: item.sourceKind,
            breakdown: breakdown,
            healthReasons: health.reasons, satietyReasons: satiety.reasons,
            dietaryWarnings: warnings)
    }

    // MARK: - Effective components

    struct EffectiveComponents {
        var components: [MenuItemComponent]
        var oilLevel: OilLevel
        var portionMultiplier: Double
    }

    static func effectiveComponents(item: MenuItem, config: ItemConfiguration) -> EffectiveComponents {
        var components = item.components
        var oilLevel = config.oilLevelOverride ?? item.defaultOilLevel
        var portion = 1.0

        // Apply selected modifications' effects.
        for mod in item.modifications where config.selectedModificationIDs.contains(mod.id) {
            switch mod.effect {
            case .scaleComponent(let id, let factor):
                components = components.map { c in
                    guard c.id == id else { return c }
                    var copy = c
                    copy.grams *= factor
                    copy.base = copy.base * factor
                    return copy
                }
            case .removeComponent(let id):
                components.removeAll { $0.id == id }
            case .addComponent(let comp):
                components.append(comp)
            case .scalePortion(let factor):
                portion *= factor
            case .setOil(let level):
                oilLevel = config.oilLevelOverride ?? level
            case .none:
                break
            }
        }

        // Ad-hoc config edits.
        components.removeAll { config.removedComponentIDs.contains($0.id) }
        for (id, factor) in config.componentScaleOverrides {
            components = components.map { c in
                guard c.id == id else { return c }
                var copy = c
                copy.grams *= factor
                copy.base = copy.base * factor
                return copy
            }
        }
        components.append(contentsOf: config.extraComponents)

        return EffectiveComponents(components: components, oilLevel: oilLevel, portionMultiplier: portion)
    }

    // MARK: - Nutrition paths

    private static func estimatedNutrition(components: [MenuItemComponent],
                                           oilLevel: OilLevel,
                                           customOilGrams: Double?,
                                           breakdown: inout NutritionEstimateBreakdown) -> ResolvedNutrition {
        var total = ResolvedNutrition.zero
        var oilCalories = 0.0
        var oilGrams = 0.0
        var oilDetails: [String] = []

        for c in components {
            var line = c.base
            let oil = MenuOilEstimator.estimate(
                foodName: c.name, method: c.cookingMethod, grams: c.grams,
                level: oilLevel, customGrams: customOilGrams,
                carriesOwnFat: c.kind.carriesOwnFat)
            if !oil.isZero {
                line.calories += oil.calories
                line.fat += oil.grams
                oilCalories += oil.calories
                oilGrams += oil.grams
                oilDetails.append("\(c.name): \(oil.detail)")
            }
            line.oilCalories = oil.calories
            line.oilFatGrams = oil.grams
            total = total + line
            breakdown.componentLines.append(.init(
                label: c.name, calories: line.calories, protein: line.protein,
                fat: line.fat, detail: componentDetail(c, oil: oil)))
        }
        breakdown.oilCalories = oilCalories
        breakdown.oilFatGrams = oilGrams
        breakdown.oilDetail = oilDetails.isEmpty
            ? "No added cooking oil (steamed/raw/boiled components add none)."
            : oilDetails.joined(separator: "  •  ")
        total.oilCalories = oilCalories
        total.oilFatGrams = oilGrams
        return total
    }

    /// Official path: start from the published macros verbatim, then apply only
    /// the explicit macro deltas from modification components. No cooking oil is
    /// ever added here; the official numbers already include it.
    private static func officialNutrition(item: MenuItem,
                                          config: ItemConfiguration,
                                          components: [MenuItemComponent],
                                          breakdown: inout NutritionEstimateBreakdown) -> ResolvedNutrition {
        var total = item.officialNutrition ?? .zero
        breakdown.componentLines.append(.init(
            label: item.name, calories: total.calories, protein: total.protein,
            fat: total.fat, detail: "Official nutrition (used as published)"))

        // Modification add/remove/scale deltas relative to the item's own
        // component list (so "no cheese" / "add bacon" still change the totals),
        // without ever layering estimated cooking oil on official numbers.
        let baseIDs = Set(item.components.map(\.id))
        for mod in item.modifications where config.selectedModificationIDs.contains(mod.id) {
            switch mod.effect {
            case .addComponent(let comp):
                total = total + comp.base
                breakdown.componentLines.append(.init(label: "+ \(comp.name)", calories: comp.base.calories,
                                                      protein: comp.base.protein, fat: comp.base.fat,
                                                      detail: "Added"))
            case .removeComponent(let id):
                if let c = item.components.first(where: { $0.id == id }) {
                    total = total + (c.base * -1)
                    breakdown.componentLines.append(.init(label: "− \(c.name)", calories: -c.base.calories,
                                                          protein: -c.base.protein, fat: -c.base.fat,
                                                          detail: "Removed"))
                }
            case .scaleComponent(let id, let factor):
                if baseIDs.contains(id), let c = item.components.first(where: { $0.id == id }) {
                    total = total + (c.base * (factor - 1))
                }
            default:
                break
            }
        }
        for comp in config.extraComponents { total = total + comp.base }
        breakdown.oilDetail = "Official nutrition already includes any cooking oil."
        return total
    }

    // MARK: - Helpers

    private static func componentDetail(_ c: MenuItemComponent, oil: OilEstimate) -> String {
        var parts = ["\(Int(c.grams.rounded())) g", c.cookingMethod.label]
        if !oil.isZero { parts.append("+\(Int(oil.calories.rounded())) kcal oil") }
        return parts.joined(separator: " · ")
    }

    /// When an official item has no component breakdown, fabricate a single
    /// component from its macros so volume-based scoring still has something to
    /// read. Grams are inferred from a neutral calorie density.
    private static func syntheticComponents(from n: ResolvedNutrition) -> [MenuItemComponent] {
        let grams = max(50, n.calories / 1.5)
        return [MenuItemComponent(name: "Item", kind: .main, grams: grams, base: n, cookingMethod: .unknown, removable: false)]
    }

    private static func resolvedConfidence(item: MenuItem, config: ItemConfiguration, usesOfficial: Bool) -> NutritionConfidence {
        if usesOfficial {
            // Heavy customization erodes even official certainty a little.
            return config.selectedModificationIDs.isEmpty && config.extraComponents.isEmpty ? .high : .medium
        }
        // Every added modification adds uncertainty.
        let mods = config.selectedModificationIDs.count + config.extraComponents.count
        if mods >= 3 { return NutritionConfidence.min(item.baseConfidence, .low) }
        if mods >= 1 { return NutritionConfidence.min(item.baseConfidence, .medium) }
        return item.baseConfidence
    }

    private static func dietaryWarnings(item: MenuItem, nutrition: ResolvedNutrition,
                                        components: [MenuItemComponent], profile: ScoringProfile) -> [String] {
        var warnings: [String] = []
        if nutrition.sodium >= profile.sodiumLimit * 0.6 {
            warnings.append("High sodium: \(Int(nutrition.sodium)) mg in one serving")
        }
        let profilesByName = Dictionary(FoodNutritionTable.all.map { ($0.canonicalName, $0) }, uniquingKeysWith: { a, _ in a })
        for restriction in profile.restrictions where restriction == .vegetarian || restriction == .vegan {
            let violates = components.contains { c in
                let tags = profilesByName[c.name]?.dietaryTags ?? []
                return !tags.contains(restriction)
            }
            if violates { warnings.append("Not \(restriction.label.lowercased())") }
        }
        return warnings
    }
}
