import SwiftUI
import SwiftData

/// View and edit a saved meal.
struct MealDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]
    @Bindable var meal: MealLog
    @State private var confirmDelete = false
    /// Loaded once on appear instead of decoded from disk inside the body:
    /// this Form re-renders on every keystroke in its text fields, and a
    /// multi-photo meal would re-decode every JPEG per character otherwise.
    @State private var photos: [UIImage] = []

    var body: some View {
        Form {
            if !photos.isEmpty {
                Section {
                    if photos.count == 1, let image = photos.first {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(photos.enumerated()), id: \.offset) { _, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 180, height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }

            Section {
                Text(meal.honestSummary)
                    .font(.callout.weight(.semibold))
                ConfidenceBadge(confidence: meal.confidence)
            }

            Section("Nutrition Analysis") {
                MealNutritionAnalysisView(meal: meal, settings: settingsList.first)
            }

            Section("Meal") {
                Picker("Type", selection: Binding(get: { meal.mealType }, set: { meal.mealType = $0 })) {
                    ForEach(MealType.allCases) { Text($0.label).tag($0) }
                }
                DatePicker("Time", selection: $meal.date)
            }

            if !meal.items.isEmpty {
                Section("Foods") {
                    ForEach(meal.items, id: \.persistentModelID) { item in
                        FoodItemEditorRow(item: item, onChanged: recalcTotals)
                    }
                    .onDelete { offsets in
                        let sorted = meal.items
                        for index in offsets {
                            meal.foodItems?.removeAll { $0 === sorted[index] }
                        }
                        recalcTotals()
                    }
                }
            }

            Section("Totals") {
                field("Calories", value: $meal.calories, unit: "kcal")
                field("Protein", value: $meal.protein, unit: "g")
                field("Carbs", value: $meal.carbs, unit: "g")
                field("Fat", value: $meal.fat, unit: "g")
                field("Fiber", value: $meal.fiber, unit: "g")
                field("Sodium", value: $meal.sodium, unit: "mg")
            }

            Section("Uncertainty") {
                field("Range low", value: $meal.calorieLow, unit: "kcal")
                field("Range high", value: $meal.calorieHigh, unit: "kcal")
                field("Hidden oil low", value: $meal.hiddenOilLow, unit: "kcal")
                field("Hidden oil high", value: $meal.hiddenOilHigh, unit: "kcal")
            }

            Section("Notes") {
                TextField("Notes", text: $meal.notes, axis: .vertical)
            }

            Section {
                Button("Delete Meal", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(meal.mealType.label)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .onAppear {
            if photos.isEmpty {
                photos = meal.allPhotoPaths.compactMap { ImageStore.load($0) }
            }
        }
        .confirmationDialog("Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                ImageStore.deleteAll(meal.allPhotoPaths)
                context.delete(meal)
                dismiss()
            }
        }
    }

    /// Recomputes the meal's totals from its food items, same as
    /// MealDraftEditor's pre-save version, so editing a food item's grams,
    /// calories, macros, or cooking method (which itself scales grams'
    /// nutrients — see FoodItemEditorRow) here after the meal is already
    /// saved keeps Totals, the food log, and the dashboard's eaten/remaining
    /// figures in sync instead of showing whatever was true at save time.
    private func recalcTotals() {
        let items = meal.items
        guard !items.isEmpty else { return }
        meal.calories = items.reduce(0) { $0 + $1.calories }
        meal.protein = items.reduce(0) { $0 + $1.protein }
        meal.carbs = items.reduce(0) { $0 + $1.carbs }
        meal.fat = items.reduce(0) { $0 + $1.fat }
        meal.fiber = items.reduce(0) { $0 + $1.fiber }
        meal.sodium = items.reduce(0) { $0 + $1.sodium }
        let oil = HiddenOilEstimator.estimate(forFoodItems: items)
        meal.hiddenOilLow = oil.low.rounded()
        meal.hiddenOilHigh = oil.high.rounded()
        meal.calorieLow = (meal.calories * 0.85).rounded()
        meal.calorieHigh = (meal.calories * 1.1 + oil.high).rounded()
    }

    private func field(_ label: String, value: Binding<Double>, unit: String) -> some View {
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
}
