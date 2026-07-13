import Foundation
import SwiftData

/// Logs a meal cart into the app's normal food history. The resulting `MealLog`
/// and its `FoodItem`s are indistinguishable from a manually logged meal, so
/// every downstream system (daily calories/macros, remaining targets, nutrition
/// and consistency scores, goal tracking, trends, and warnings) picks it up
/// automatically, and the meal stays fully editable afterward.
enum MealCartLogger {

    struct Options {
        var mealType: MealType
        var date: Date = .now
        var mealName: String = ""
        var notes: String = ""
        /// When false, only `portionPercent` of the cart is counted as eaten.
        var ateFullAmount: Bool = true
        /// 0–100; ignored when `ateFullAmount` is true.
        var portionPercent: Double = 100
        var saveAsReusableMeal: Bool = false
        var photoPath: String? = nil
    }

    enum LogResult: Equatable {
        case logged
        /// The same cart was logged moments ago; ignored to prevent a double tap
        /// from creating two meals.
        case duplicateIgnored
        case emptyCart
    }

    // Recent log signatures → timestamp, guarding against accidental double logs.
    private static var recentSignatures: [String: Date] = [:]
    private static let duplicateWindow: TimeInterval = 4

    /// Reset the duplicate guard: used by tests and safe to call anytime.
    static func resetDuplicateGuard() { recentSignatures.removeAll() }

    @discardableResult
    static func log(lines: [CartLine], options: Options, settings: UserSettings?,
                    context: ModelContext, now: Date = .now) -> LogResult {
        guard !lines.isEmpty else { return .emptyCart }

        let signature = signatureFor(lines: lines, options: options)
        pruneSignatures(now: now)
        if let last = recentSignatures[signature], now.timeIntervalSince(last) < duplicateWindow {
            return .duplicateIgnored
        }
        recentSignatures[signature] = now

        let fraction = options.ateFullAmount ? 1.0 : max(0, min(1, options.portionPercent / 100))
        let summary = CartManager.summary(for: lines)
        let total = summary.nutrition * fraction

        // One FoodItem per cart line, scaled by the eaten fraction.
        var foodItems: [FoodItem] = []
        for line in lines {
            let n = line.lineNutrition * fraction
            let grams = componentGrams(for: line) * fraction
            let name = line.modificationSummary.isEmpty
                ? "\(line.itemName)\(line.quantity > 1 ? " ×\(line.quantity)" : "")"
                : "\(line.itemName) (\(line.modificationSummary))"
            foodItems.append(FoodItem(
                name: name, grams: grams, calories: n.calories, protein: n.protein,
                carbs: n.carbs, fat: n.fat, fiber: n.fiber, sodium: n.sodium,
                cookingMethod: cookingMethod(for: line),
                confidence: line.confidence.scalar))
        }

        let restaurantNames = Array(Set(lines.map(\.restaurantName))).sorted()
        var notesParts: [String] = []
        if !options.mealName.isEmpty { notesParts.append(options.mealName) }
        notesParts.append("Logged from Menu Checker · " + restaurantNames.joined(separator: ", "))
        if !options.ateFullAmount { notesParts.append("Ate \(Int(options.portionPercent))% of the cart") }
        if !options.notes.isEmpty { notesParts.append(options.notes) }

        let meal = MealLog(
            date: options.date,
            mealType: options.mealType,
            photoPath: options.photoPath,
            calories: total.calories,
            protein: total.protein,
            carbs: total.carbs,
            fat: total.fat,
            fiber: total.fiber,
            sodium: total.sodium,
            confidence: summary.confidence.scalar,
            calorieLow: total.calories * 0.9,
            calorieHigh: total.calories * 1.12,
            // Menu Checker calories already include estimated cooking oil, so we
            // deliberately do NOT add a hidden-oil range here: that would
            // double-count. Oil is already inside `total`.
            hiddenOilLow: 0,
            hiddenOilHigh: 0,
            notes: notesParts.joined(separator: " · "),
            foodItems: foodItems,
            healthScore: summary.combinedHealthScore,
            satietyScore: summary.combinedSatietyScore,
            facts: menuFacts(summary: summary, restaurants: restaurantNames),
            concerns: summary.warnings.isEmpty ? ["No major concerns for a balanced day."] : summary.warnings,
            analysisSummary: "Menu Checker: \(Int(summary.combinedHealthScore))/100 health, \(Int(summary.combinedSatietyScore))/100 satiety.",
            analysisState: .completed)
        context.insert(meal)

        if options.saveAsReusableMeal {
            saveReusableMeal(name: options.mealName.isEmpty ? (restaurantNames.first ?? "Menu meal") : options.mealName,
                             total: total, context: context)
        }

        try? context.save()
        // NOTE: the cart is cleared by the caller (`clearCart`) once logging has
        // succeeded, kept separate so the duplicate guard can inspect the same
        // lines on a rapid second tap.
        return .logged
    }

    /// Clear the logged cart. Call only after `log` returns `.logged`.
    static func clearCart(_ lines: [CartLine], context: ModelContext) {
        for line in lines { context.delete(line) }
        try? context.save()
    }

    // MARK: Helpers

    private static func menuFacts(summary: CartSummary, restaurants: [String]) -> [String] {
        var facts: [String] = []
        let n = summary.nutrition
        if n.calories > 0, n.protein / max(1, n.calories) * 100 >= 6 { facts.append("High protein for the calories") }
        if n.fiber >= 8 { facts.append("Good fibre content") }
        facts.append("Estimated from menu items: confidence \(summary.confidence.label.lowercased())")
        return Array(facts.prefix(4))
    }

    private static func componentGrams(for line: CartLine) -> Double {
        guard let spec = line.spec else { return 0 }
        let effective = MenuItemResolver.effectiveComponents(item: spec.item, config: spec.config)
        let perUnit = effective.components.reduce(0) { $0 + $1.grams } * effective.portionMultiplier
        return perUnit * Double(max(1, line.quantity))
    }

    private static func cookingMethod(for line: CartLine) -> CookingMethod {
        guard let spec = line.spec else { return .unknown }
        // Represent the line by its most oil-relevant component method.
        let methods = spec.item.components.map(\.cookingMethod)
        if methods.contains(.deepFried) { return .deepFried }
        if methods.contains(.stirFried) { return .stirFried }
        if let first = methods.first(where: { $0 != .unknown }) { return first }
        return .unknown
    }

    private static func saveReusableMeal(name: String, total: ResolvedNutrition, context: ModelContext) {
        let preset = FoodPreset(name: name, serving: "1 meal",
                                calories: total.calories, protein: total.protein,
                                carbs: total.carbs, fat: total.fat, fiber: total.fiber,
                                sodium: total.sodium, category: "Menu Checker",
                                notes: "Saved from a Menu Checker meal")
        context.insert(preset)
    }

    private static func signatureFor(lines: [CartLine], options: Options) -> String {
        let ids = lines.map { "\($0.id.uuidString):\($0.quantity)" }.sorted().joined(separator: ",")
        let minute = Int(options.date.timeIntervalSince1970 / 60)
        return "\(options.mealType.rawValue)|\(minute)|\(ids)"
    }

    private static func pruneSignatures(now: Date) {
        recentSignatures = recentSignatures.filter { now.timeIntervalSince($0.value) < 60 }
    }
}
