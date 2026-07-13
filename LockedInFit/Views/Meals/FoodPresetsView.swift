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
    @State private var referenceGrams: Double = 0
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
                    TextField("Serving label (e.g. 1 bowl, 180 g)", text: $serving)
                    TextField("Category", text: $category)
                    Picker("Cooking method", selection: $cookingMethod) {
                        ForEach(CookingMethod.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    field("Weight", value: $referenceGrams, unit: "g")
                    field("Calories", value: $calories, unit: "kcal")
                    field("Protein", value: $protein, unit: "g")
                    field("Carbs", value: $carbs, unit: "g")
                    field("Fat", value: $fat, unit: "g")
                    field("Fiber", value: $fiber, unit: "g")
                    field("Sodium", value: $sodium, unit: "mg")
                } header: {
                    Text("Nutrition per serving")
                } footer: {
                    Text("Weight is what makes this preset reusable at other portion sizes: when a logged meal's amount differs from this weight, the calories and macros above are scaled proportionally instead of applied as-is.")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(preset == nil ? "New Preset" : "Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
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
        // Falls back to whatever can be parsed out of the serving label for
        // presets saved before the Weight field existed, so editing one
        // shows a sensible starting value instead of a blank 0.
        referenceGrams = preset.effectiveReferenceGrams
        protein = preset.protein; carbs = preset.carbs; fat = preset.fat
        fiber = preset.fiber; sodium = preset.sodium; category = preset.category
        notes = preset.notes; cookingMethod = preset.cookingMethod
    }

    private func save() {
        // Untrimmed whitespace here is invisible in the UI but permanent in
        // the stored name/category: a preset saved with a trailing space
        // would never again match FoodPresetSyncService.matchingPreset
        // (which normalizes what it's comparing against, but can't fix what
        // got stored), and an untrimmed category silently starts its own
        // section in the list below instead of joining the one that looks
        // identical.
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategory = cleanCategory.isEmpty ? "General" : cleanCategory
        if let preset {
            preset.name = cleanName; preset.serving = serving; preset.referenceGrams = referenceGrams
            preset.calories = calories
            preset.protein = protein; preset.carbs = carbs; preset.fat = fat
            preset.fiber = fiber; preset.sodium = sodium; preset.category = resolvedCategory
            preset.notes = notes; preset.cookingMethod = cookingMethod
        } else {
            context.insert(FoodPreset(name: cleanName, serving: serving, referenceGrams: referenceGrams,
                                      calories: calories, protein: protein, carbs: carbs, fat: fat,
                                      fiber: fiber, sodium: sodium, category: resolvedCategory,
                                      notes: notes, cookingMethod: cookingMethod))
        }
        dismiss()
    }
}
