import SwiftUI
import SwiftData

/// Quick manual meal entry: type macros directly or start from a preset.
struct AddMealView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodPreset.name) private var presets: [FoodPreset]

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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Time", selection: $date)
                }

                Section("From presets") {
                    Button {
                        showPresetPicker = true
                    } label: {
                        Label("Add preset food", systemImage: "plus.circle")
                    }
                    ForEach(addedItems, id: \.persistentModelID) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text("\(Int(item.calories)) kcal")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            subtractItem(addedItems[index])
                        }
                        addedItems.remove(atOffsets: offsets)
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
                                        cookingMethod: preset.cookingMethod)
                    addedItems.append(item)
                    calories += preset.calories
                    protein += preset.protein
                    carbs += preset.carbs
                    fat += preset.fat
                    fiber += preset.fiber
                    sodium += preset.sodium
                }
            }
        }
    }

    private func subtractItem(_ item: FoodItem) {
        calories -= item.calories
        protein -= item.protein
        carbs -= item.carbs
        fat -= item.fat
        fiber -= item.fiber
        sodium -= item.sodium
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
