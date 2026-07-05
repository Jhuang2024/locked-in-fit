import SwiftUI
import SwiftData

/// View and edit a saved meal.
struct MealDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var meal: MealLog
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if let image = ImageStore.load(meal.photoPath) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                Text(meal.honestSummary)
                    .font(.callout.weight(.semibold))
                ConfidenceBadge(confidence: meal.confidence)
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
                        FoodItemEditorRow(item: item)
                    }
                    .onDelete { offsets in
                        let sorted = meal.items
                        for index in offsets {
                            meal.foodItems?.removeAll { $0 === sorted[index] }
                        }
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
        .confirmationDialog("Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                ImageStore.delete(meal.photoPath)
                context.delete(meal)
                dismiss()
            }
        }
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
