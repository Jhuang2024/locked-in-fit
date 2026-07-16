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
    @State private var showSpeech = false

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
                    Button {
                        showSpeech = true
                    } label: {
                        Label("Speak your meal", systemImage: "mic.fill")
                    }
                    if let estimateError {
                        Text(estimateError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Describe It")
                } footer: {
                    Text("Type or speak the meal in plain language and its calories/macros get added to the totals below. Typing uses the same AI gateway as photo analysis (OpenRouter, falling back to BazaarLink; Settings → AI Analysis); speech is parsed on-device with the same oil rules as Menu Checker.")
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
            .sheet(isPresented: $showSpeech) {
                SpeechMealDictationView { entries, detectedMealType in
                    applyParsedEntries(entries, mealType: detectedMealType)
                }
            }
            .sheet(isPresented: $showPresetPicker) {
                PresetPickerView { preset, portion in
                    // The portion comes from the user (entered right after
                    // picking, in PresetAmountEntryView — grams for weighed
                    // foods, a serving count for countable ones), never from
                    // a preset default. grams and the scaled nutrition are
                    // computed together there so they describe the same
                    // amount of food from the moment the item is created:
                    // FoodItemEditorRow scales proportionally from whatever
                    // pair it starts with, so a mismatched starting pair
                    // would throw every later edit off by that same wrong
                    // ratio.
                    let item = FoodItem(name: preset.name, grams: portion.grams,
                                        calories: preset.calories * portion.ratio,
                                        protein: preset.protein * portion.ratio,
                                        carbs: preset.carbs * portion.ratio,
                                        fat: preset.fat * portion.ratio,
                                        fiber: preset.fiber * portion.ratio,
                                        sodium: preset.sodium * portion.ratio,
                                        cookingMethod: preset.cookingMethod, order: addedItems.count,
                                        fromPreset: true, weighed: portion.weighed)
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
        // guess for the same food name: see FoodItemEstimate.makeFoodItem.
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

    /// Add speech-parsed foods into the manual meal: additive to typing, never a
    /// replacement. The user has already reviewed and corrected these.
    private func applyParsedEntries(_ entries: [ParsedMealEntry], mealType parsedType: MealType) {
        guard !entries.isEmpty else { return }
        mealType = parsedType
        let baseOrder = addedItems.count
        let items = entries.enumerated().map { index, entry in
            FoodItem(name: entry.name, grams: entry.grams,
                     calories: entry.nutrition.calories, protein: entry.nutrition.protein,
                     carbs: entry.nutrition.carbs, fat: entry.nutrition.fat,
                     fiber: entry.nutrition.fiber, sodium: entry.nutrition.sodium,
                     cookingMethod: entry.method, confidence: 0.6, order: baseOrder + index)
        }
        addedItems.append(contentsOf: items)
        recalcTotals()
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

/// What the user said they ate of a preset: the grams to record on the
/// FoodItem (0 when unknowable, e.g. servings of a preset with no saved
/// weight) and the factor to scale the preset's saved nutrition by. The two
/// are computed together so they always describe the same amount of food.
struct PresetPortion {
    var grams: Double
    var ratio: Double
    /// True when the user said the gram amount came off a scale, exempting
    /// the item from the portion-underestimation uplift.
    var weighed: Bool = false
}

/// Searchable preset picker used by AddMealView. Picking a preset doesn't
/// add it directly: presets carry no default portion, so the user first
/// enters how much they ate (PresetAmountEntryView) and only then does
/// `onPick` fire with both the preset and that portion.
struct PresetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodPreset.name) private var presets: [FoodPreset]
    @State private var search = ""
    @State private var pendingPreset: FoodPreset?
    let onPick: (FoodPreset, PresetPortion) -> Void

    private var filtered: [FoodPreset] {
        search.isEmpty ? presets : presets.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { preset in
                Button {
                    pendingPreset = preset
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
            .sheet(item: $pendingPreset) { preset in
                PresetAmountEntryView(preset: preset) { portion in
                    onPick(preset, portion)
                    dismiss()
                }
            }
        }
    }
}

/// Second step of picking a preset: say how much was eaten. Starts blank on
/// purpose — a preset has no default portion, so the user always types the
/// actual amount instead of accepting a seeded number.
///
/// Two ways to answer, because not every food is weighable: **Servings**
/// counts whole pieces of the preset's saved serving (2 hardboiled eggs —
/// nobody knows what one weighs, but the preset does), **Grams** weighs bulk
/// foods (rice, chicken breast). Countable foods (`isCountedInServings`) and
/// presets with no usable reference weight start on Servings; everything
/// else starts on Grams.
struct PresetAmountEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let preset: FoodPreset
    let onConfirm: (PresetPortion) -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case servings, grams
        var id: String { rawValue }
        var label: String { self == .servings ? "Servings" : "Grams" }
    }

    @State private var mode: Mode
    @State private var servings: Double?
    @State private var grams: Double?
    @State private var weighed = false
    @FocusState private var amountFocused: Bool

    init(preset: FoodPreset, onConfirm: @escaping (PresetPortion) -> Void) {
        self.preset = preset
        self.onConfirm = onConfirm
        _mode = State(initialValue:
            preset.isCountedInServings || preset.effectiveReferenceGrams <= 0 ? .servings : .grams)
    }

    private var referenceGrams: Double { preset.effectiveReferenceGrams }

    private var portion: PresetPortion? {
        switch mode {
        case .servings:
            guard let servings, servings > 0 else { return nil }
            return PresetPortion(grams: referenceGrams > 0 ? servings * referenceGrams : 0,
                                 ratio: servings)
        case .grams:
            guard let grams, grams > 0 else { return nil }
            return PresetPortion(grams: grams,
                                 ratio: referenceGrams > 0 ? grams / referenceGrams : 1,
                                 weighed: weighed)
        }
    }

    /// What "1 serving" means for this preset, best label first: the saved
    /// serving text ("1 bowl", "180 g"), else the reference weight.
    private var servingDescription: String {
        let label = preset.serving.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        if referenceGrams > 0 { return "\(referenceGrams.formatted()) g" }
        return "the amounts saved on this preset"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Measure by", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text(mode == .servings ? "Servings" : "Amount")
                        Spacer()
                        if mode == .servings {
                            TextField("How many", value: $servings, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .focused($amountFocused)
                            Text("×").foregroundStyle(.secondary).font(.caption)
                        } else {
                            TextField("Weight", value: $grams, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .focused($amountFocused)
                            Text("g").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    if mode == .grams {
                        Toggle(isOn: $weighed) {
                            Label("Weighed on a scale", systemImage: "scalemass")
                        }
                    }
                    if let portion {
                        LabeledContent("Adds") {
                            Text(portion.grams > 0
                                 ? "\(Int((preset.calories * portion.ratio).rounded())) kcal · \(portion.grams.formatted()) g"
                                 : "\(Int((preset.calories * portion.ratio).rounded())) kcal")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(preset.name)
                } footer: {
                    if mode == .servings {
                        Text("1 serving = \(servingDescription). Half servings like 0.5 work too.")
                    } else if referenceGrams > 0 {
                        Text("Calories and macros are scaled from the preset's saved nutrition (per \(referenceGrams.formatted()) g). Turn on Weighed on a scale if the amount came off a food scale — weighed items skip the Portion estimation adjustment.")
                    } else {
                        Text("This preset has no saved weight, so its nutrition is applied as-is regardless of the amount you enter. Switch to Servings, or set a Weight on the preset.")
                    }
                }
            }
            .navigationTitle("How Much?")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let portion {
                            onConfirm(portion)
                        }
                        dismiss()
                    }
                    .disabled(portion == nil)
                }
            }
            .onAppear { amountFocused = true }
            .onChange(of: mode) { amountFocused = true }
            .presentationDetents([.height(320), .medium])
        }
    }
}
