import SwiftUI
import SwiftData

struct FoodPresetsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodPreset.name) private var presets: [FoodPreset]
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]
    @State private var search = ""
    @State private var editing: FoodPreset?
    @State private var showNew = false
    @State private var sort: PresetSort = .name

    enum PresetSort: String, CaseIterable, Identifiable {
        case name, rating, health, satiety
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: return "Name"
            case .rating: return "Highest rated"
            case .health: return "Health Score"
            case .satiety: return "Satiety Score"
            }
        }
        var flatSectionTitle: String {
            switch self {
            case .name: return ""
            case .rating: return "Highest rated first"
            case .health: return "Healthiest first"
            case .satiety: return "Most filling first"
            }
        }
    }

    /// Same personalized profile the Menu Checker screens build, so a preset
    /// scores exactly like a menu item with identical macros would today.
    private var profile: ScoringProfile {
        ScoringProfileBuilder.make(settings: settingsList.first, goal: goals.first, meals: meals)
    }

    private var filtered: [FoodPreset] {
        search.isEmpty ? presets : presets.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var grouped: [(category: String, items: [FoodPreset])] {
        Dictionary(grouping: filtered, by: \.category)
            .map { (category: $0.key, items: $0.value) }
            .sorted { $0.category < $1.category }
    }

    /// The non-name sorts are a single flat list (best on top, ties by name);
    /// category sections would bury a top preset in whatever group it happens
    /// to live in, which defeats the point of sorting.
    private var flatSorted: [FoodPreset] {
        switch sort {
        case .name:
            return filtered
        case .rating:
            return filtered.sorted {
                if $0.rating != $1.rating { return $0.rating > $1.rating }
                return $0.name < $1.name
            }
        case .health, .satiety:
            // Score each preset once, not once per comparison.
            let scored = filtered.map { ($0, PresetScoringService.scores(for: $0, profile: profile)) }
            return scored.sorted {
                let l = sort == .health ? $0.1.health : $0.1.satiety
                let r = sort == .health ? $1.1.health : $1.1.satiety
                if l != r { return l > r }
                return $0.0.name < $1.0.name
            }.map(\.0)
        }
    }

    private func presetRow(_ preset: FoodPreset) -> some View {
        let scores = PresetScoringService.scores(for: preset, profile: profile)
        return Button { editing = preset } label: {
            FoodPresetRowView(preset: preset, health: scores.health, satiety: scores.satiety, showsCalorieDensity: true)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        List {
            if sort == .name {
                ForEach(grouped, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.items) { preset in
                            presetRow(preset)
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(group.items[index]) }
                        }
                    }
                }
            } else {
                let sorted = flatSorted
                Section(sort.flatSectionTitle) {
                    ForEach(sorted) { preset in
                        presetRow(preset)
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(sorted[index]) }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Food Presets")
        .toolbar {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(PresetSort.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort presets")
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
    @State private var rating = 0

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
                    Text("Weight is what makes this preset reusable at any portion size: it's not a default amount, just the weight the nutrition above describes. When you log this food you enter the amount you actually ate, and the calories and macros are scaled proportionally from this weight.")
                }
                Section {
                    StarRatingView(rating: $rating)
                } header: {
                    Text("Your Rating")
                } footer: {
                    Text("Rated foods can be sorted to the top of this list.")
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
        rating = preset.rating
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
            preset.rating = FoodRatingService.clamped(rating)
        } else {
            let new = FoodPreset(name: cleanName, serving: serving, referenceGrams: referenceGrams,
                                 calories: calories, protein: protein, carbs: carbs, fat: fat,
                                 fiber: fiber, sodium: sodium, category: resolvedCategory,
                                 notes: notes, cookingMethod: cookingMethod)
            new.rating = FoodRatingService.clamped(rating)
            context.insert(new)
        }
        dismiss()
    }
}
