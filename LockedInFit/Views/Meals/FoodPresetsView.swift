import SwiftUI
import SwiftData

struct FoodPresetsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodPreset.name) private var presets: [FoodPreset]
    @State private var search = ""
    @State private var editing: FoodPreset?
    @State private var showNew = false

    private var grouped: [(category: String, items: [FoodPreset])] {
        let filtered = search.isEmpty ? presets : presets.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return Dictionary(grouping: filtered, by: \.category)
            .map { (category: $0.key, items: $0.value) }
            .sorted { $0.category < $1.category }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.category) { group in
                Section(group.category) {
                    ForEach(group.items) { preset in
                        Button { editing = preset } label: {
                            FoodPresetRowView(preset: preset)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(group.items[index]) }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Food Presets")
        .toolbar {
            Button { showNew = true } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editing) { preset in
            PresetEditorView(preset: preset)
        }
        .sheet(isPresented: $showNew) {
            PresetEditorView(preset: nil)
        }
    }
}

struct PresetEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let preset: FoodPreset?

    @State private var name = ""
    @State private var serving = ""
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0
    @State private var fiber: Double = 0
    @State private var sodium: Double = 0
    @State private var category = "General"
    @State private var notes = ""
    @State private var cookingMethod: CookingMethod = .unknown

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Serving (e.g. 1 bowl, 180 g)", text: $serving)
                    TextField("Category", text: $category)
                    Picker("Cooking method", selection: $cookingMethod) {
                        ForEach(CookingMethod.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Nutrition per serving") {
                    field("Calories", value: $calories, unit: "kcal")
                    field("Protein", value: $protein, unit: "g")
                    field("Carbs", value: $carbs, unit: "g")
                    field("Fat", value: $fat, unit: "g")
                    field("Fiber", value: $fiber, unit: "g")
                    field("Sodium", value: $sodium, unit: "mg")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(preset == nil ? "New Preset" : "Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
            .onAppear { load() }
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

    private func load() {
        guard let preset else { return }
        name = preset.name; serving = preset.serving; calories = preset.calories
        protein = preset.protein; carbs = preset.carbs; fat = preset.fat
        fiber = preset.fiber; sodium = preset.sodium; category = preset.category
        notes = preset.notes; cookingMethod = preset.cookingMethod
    }

    private func save() {
        if let preset {
            preset.name = name; preset.serving = serving; preset.calories = calories
            preset.protein = protein; preset.carbs = carbs; preset.fat = fat
            preset.fiber = fiber; preset.sodium = sodium; preset.category = category
            preset.notes = notes; preset.cookingMethod = cookingMethod
        } else {
            context.insert(FoodPreset(name: name, serving: serving, calories: calories,
                                      protein: protein, carbs: carbs, fat: fat, fiber: fiber,
                                      sodium: sodium, category: category, notes: notes,
                                      cookingMethod: cookingMethod))
        }
        dismiss()
    }
}
