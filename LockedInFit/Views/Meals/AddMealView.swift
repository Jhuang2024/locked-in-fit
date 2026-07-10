import SwiftUI
import SwiftData

/// Quick manual meal entry: type macros directly or start from a preset.
struct AddMealView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodPreset.name) private var presets: [FoodPreset]
    @Query private var settingsList: [UserSettings]

    @State private var mealType: MealType = .guess()
    @State private var date: Date = .now
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0
    @State private var fiber: Double = 0
    @State private var sodium: Double = 0
    @State private var notes = ""
    @State private var addedItems: [FoodItem] = []
    @State private var showPresetPicker = false
    @State private var mealDescription = ""
    @State private var estimating = false
    @State private var estimateError: String?

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Time", selection: $date)
                }

                Section {
                    TextField("What did you eat? e.g. \"grilled chicken breast, rice, and broccoli\"",
                              text: $mealDescription, axis: .vertical)
                        .lineLimit(2...4)
                    Button {
                        estimateFromDescription()
                    } label: {
                        if estimating {
                            HStack { ProgressView(); Text("Estimating…") }
                        } else {
                            Label("Estimate Calories", systemImage: "text.magnifyingglass")
                        }
                    }
                    .disabled(estimating || mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let estimateError {
                        Text(estimateError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Describe It")
                } footer: {
                    Text("Describe the meal in plain language and its calories/macros get added to the totals below. Uses the same OpenRouter model as photo analysis (Settings → AI Analysis).")
                }

                Section("From presets") {
                    Button {
                        showPresetPicker = true
                    } label: {
                        Label("Add preset food", systemImage: "plus.circle")
                    }
                }

                if !addedItems.isEmpty {
                    Section("Foods") {
                        ForEach(addedItems, id: \.persistentModelID) { item in
                            FoodItemEditorRow(item: item, onChanged: recalcTotals)
                        }
                        .onDelete { offsets in
                            addedItems.remove(atOffsets: offsets)
                            recalcTotals()
                        }
                    }
                }

                Section("Totals") {
                    macroField("Calories", value: $calories, unit: "kcal")
                    macroField("Protein", value: $protein, unit: "g")
                    macroField("Carbs", value: $carbs, unit: "g")
                    macroField("Fat", value: $fat, unit: "g")
                    macroField("Fiber", value: $fiber, unit: "g")
                    macroField("Sodium", value: $sodium, unit: "mg")
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(calories <= 0 && addedItems.isEmpty)
                }
            }
            .sheet(isPresented: $showPresetPicker) {
                PresetPickerView { preset in
                    let item = FoodItem(name: preset.name, grams: 0, calories: preset.calories,
                                        protein: preset.protein, carbs: preset.carbs, fat: preset.fat,
                                        fiber: preset.fiber, sodium: preset.sodium,
                                        cookingMethod: preset.cookingMethod, order: addedItems.count)
                    addedItems.append(item)
                    recalcTotals()
                }
            }
        }
    }

    private func estimateFromDescription() {
        let text = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        estimating = true
        estimateError = nil
        Task {
            defer { estimating = false }
            do {
                let service = AIServiceFactory.make(settings: settings)
                let aiContext = MealAnalysisContext(mealType: mealType, isLikelyHomeCooked: true)
                let estimate = try await service.analyzeMeal(description: text, context: aiContext)
                applyEstimate(estimate)
            } catch {
                estimateError = error.localizedDescription
            }
        }
    }

    private func applyEstimate(_ estimate: MealEstimate) {
        // Defaults to a matching preset's saved numbers over the AI's fresh
        // guess for the same food name — see FoodItemEstimate.makeFoodItem.
        // Order continues from whatever's already in addedItems (manual
        // entry or an earlier "Estimate Calories" pass can precede this).
        let baseOrder = addedItems.count
        let items = estimate.foodItems.enumerated().map { index, item in
            item.makeFoodItem(presets: presets, order: baseOrder + index)
        }
        addedItems.append(contentsOf: items)
        recalcTotals()
        if notes.isEmpty { notes = estimate.notes }
        mealDescription = ""
    }

    /// Totals derive from the sum of `addedItems` whenever there's at least
    /// one, so editing an item's grams, calories, macros, or cooking method
    /// in the Foods section (via FoodItemEditorRow, same editor the photo
    /// flow and the post-save meal detail screen use) keeps Totals in sync
    /// instead of showing a stale figure from whenever the item was added.
    /// Guarded on non-empty so pure manual entry (no items at all, just
    /// typed totals) is left alone rather than getting zeroed out.
    private func recalcTotals() {
        guard !addedItems.isEmpty else { return }
        calories = addedItems.reduce(0) { $0 + $1.calories }
        protein = addedItems.reduce(0) { $0 + $1.protein }
        carbs = addedItems.reduce(0) { $0 + $1.carbs }
        fat = addedItems.reduce(0) { $0 + $1.fat }
        fiber = addedItems.reduce(0) { $0 + $1.fiber }
        sodium = addedItems.reduce(0) { $0 + $1.sodium }
    }

    private func macroField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }

    private func save() {
        let oil = HiddenOilEstimator.estimate(forFoodItems: addedItems)
        let meal = MealLog(date: date, mealType: mealType,
                           calories: calories, protein: protein, carbs: carbs, fat: fat,
                           fiber: fiber, sodium: sodium,
                           confidence: addedItems.isEmpty ? 0.9 : 0.8,
                           calorieLow: calories * 0.9, calorieHigh: calories * 1.1 + oil.high,
                           hiddenOilLow: oil.low, hiddenOilHigh: oil.high,
                           notes: notes, foodItems: addedItems)
        context.insert(meal)
        FoodPresetSyncService.addMissingPresets(for: addedItems, existingPresets: presets, context: context)
        MealNutritionAnalysisRunner.analyzeInBackground(meal: meal, settings: settings, context: context)
        dismiss()
    }
}

/// Searchable preset picker used by AddMealView.
struct PresetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodPreset.name) private var presets: [FoodPreset]
    @State private var search = ""
    let onPick: (FoodPreset) -> Void

    private var filtered: [FoodPreset] {
        search.isEmpty ? presets : presets.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { preset in
                Button {
                    onPick(preset)
                    dismiss()
                } label: {
                    FoodPresetRowView(preset: preset)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search)
            .navigationTitle("Pick Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
