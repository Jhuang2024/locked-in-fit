import SwiftUI
import SwiftData

/// Clean, native editor for an AI-estimated described dish. The user can correct
/// the name and every macro; Health/Satiety scores recompute live; then add it
/// to the cart under its restaurant. Deliberately a Form (not the component-based
/// item detail) because a described dish is just editable numbers.
struct DescribedDishView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]

    let restaurant: Restaurant
    let confidence: NutritionConfidence

    @State private var name: String
    @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var fiber: Double
    @State private var sodium: Double
    @State private var quantity: Int = 1
    @State private var added = false

    init(dish: EstimatedDish, restaurant: Restaurant) {
        self.restaurant = restaurant
        self.confidence = dish.confidence
        _name = State(initialValue: dish.name)
        _calories = State(initialValue: dish.nutrition.calories)
        _protein = State(initialValue: dish.nutrition.protein)
        _carbs = State(initialValue: dish.nutrition.carbs)
        _fat = State(initialValue: dish.nutrition.fat)
        _fiber = State(initialValue: dish.nutrition.fiber)
        _sodium = State(initialValue: dish.nutrition.sodium)
    }

    private var nutrition: ResolvedNutrition {
        ResolvedNutrition(calories: calories, protein: protein, carbs: carbs,
                          fat: fat, fiber: fiber, sodium: sodium)
    }
    private var profile: ScoringProfile {
        ScoringProfileBuilder.make(settings: settingsList.first, goal: goals.first, meals: meals)
    }
    private var component: MenuItemComponent {
        MenuItemComponent(name: name, kind: .main, grams: max(50, calories / 1.8),
                          base: nutrition, cookingMethod: .unknown, removable: false)
    }
    private var health: (score: Double, reasons: [String]) {
        MenuHealthScoreCalculator.score(nutrition: nutrition, components: [component],
                                        sourceKind: .estimatedFromIngredients, profile: profile)
    }
    private var satiety: (score: Double, reasons: [String]) {
        SatietyScoreCalculator.score(nutrition: nutrition, components: [component], profile: profile)
    }

    var body: some View {
        Form {
            Section("Dish") {
                TextField("Dish name", text: $name, axis: .vertical)
                    .lineLimit(1...2)
                Text("Estimated for \(restaurant.name) · tap any number below to correct it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 18) {
                    HealthScoreGauge(score: health.score, size: 66)
                    SatietyScoreGauge(score: satiety.score, size: 66)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(health.reasons.prefix(2), id: \.self) {
                            Label($0, systemImage: "heart.fill").font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(satiety.reasons.prefix(1), id: \.self) {
                            Label($0, systemImage: "gauge.with.dots.needle.bottom.50percent").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                ConfidenceDots(confidence: confidence)
            } header: {
                Text("Scores (recalculate as you edit)")
            }

            Section("Nutrition: edit to correct") {
                macroField("Calories", value: $calories, unit: "kcal")
                macroField("Protein", value: $protein, unit: "g")
                macroField("Carbs", value: $carbs, unit: "g")
                macroField("Fat", value: $fat, unit: "g")
                macroField("Fiber", value: $fiber, unit: "g")
                macroField("Sodium", value: $sodium, unit: "mg")
            }

            Section {
                Stepper(value: $quantity, in: 1...20) {
                    Text("Quantity: \(quantity)")
                }
            }
        }
        .navigationTitle("Describe a Dish")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(added ? "Added" : "Add to cart") { addToCart() }
                    .fontWeight(.semibold)
                    .disabled(added || calories <= 0)
            }
        }
    }

    private func macroField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addToCart() {
        guard !added else { return }
        added = true
        CartManager.addDescribed(name: name, restaurant: restaurant, nutrition: nutrition,
                                 healthScore: health.score, satietyScore: satiety.score,
                                 confidence: confidence, quantity: quantity, context: context)
        dismiss()
    }
}
