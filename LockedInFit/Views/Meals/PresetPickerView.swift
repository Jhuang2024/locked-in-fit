import SwiftUI
import SwiftData

/// Searchable preset picker with a cart, used by AddMealView.
///
/// Picking a preset doesn't add it directly: presets carry no default portion,
/// so the user first enters how much they ate (PresetAmountEntryView). What
/// changed is what happens next — the food drops into a running cart and the
/// picker stays open, so a five-food meal is five picks instead of five
/// round trips through "Add preset food". `onAdd` fires once, with everything
/// in the cart, when the user taps Add.
///
/// Same idea as the Menu Checker meal cart, scoped down: this one is staging
/// for the meal being written, so it lives in `@State` for the life of the
/// sheet rather than in the store.
struct PresetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodPreset.name) private var presets: [FoodPreset]
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]
    @State private var search = ""
    @State private var pendingPreset: FoodPreset?
    @State private var lines: [PresetCartLine] = []
    @State private var showCart = false
    @State private var confirmDiscard = false
    let onAdd: ([PresetCartLine]) -> Void

    /// Same personalized profile the Food Presets screen builds, so a preset's
    /// Health/Satiety chips read identically in both places.
    private var profile: ScoringProfile {
        ScoringProfileBuilder.make(settings: settingsList.first, goal: goals.first, meals: meals)
    }

    private var filtered: [FoodPreset] {
        search.isEmpty ? presets : presets.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var totals: PresetCartTotals { PresetCartMath.totals(for: lines) }

    /// How much of this preset is already in the cart, for the row badge. Two
    /// picks of the same food stay two lines (they're usually two different
    /// portions), so this counts them.
    private func cartCount(for preset: FoodPreset) -> Int {
        lines.filter { $0.preset.persistentModelID == preset.persistentModelID }.count
    }

    var body: some View {
        NavigationStack {
            List(filtered) { preset in
                Button {
                    pendingPreset = preset
                } label: {
                    let scores = PresetScoringService.scores(for: preset, profile: profile)
                    HStack(spacing: 8) {
                        FoodPresetRowView(preset: preset, health: scores.health,
                                          satiety: scores.satiety, showsCalorieDensity: true)
                        let count = cartCount(for: preset)
                        if count > 0 {
                            let badge = count == 1 ? "In cart" : "In cart ×\(count)"
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search)
            .navigationTitle("Pick Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if lines.isEmpty { dismiss() } else { confirmDiscard = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCart = true } label: {
                        Label("Cart", systemImage: "cart")
                            .labelStyle(.iconOnly)
                            .overlay(alignment: .topTrailing) {
                                if !lines.isEmpty {
                                    Text("\(lines.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(Color.accentColor, in: Circle())
                                        .offset(x: 9, y: -9)
                                }
                            }
                    }
                    .disabled(lines.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) { if !lines.isEmpty { addBar } }
            .navigationDestination(isPresented: $showCart) {
                PresetCartReviewView(lines: $lines, onAdd: addEverything)
            }
            .sheet(item: $pendingPreset) { preset in
                PresetAmountEntryView(preset: preset) { portion in
                    lines.append(PresetCartLine(preset: preset, portion: portion))
                }
            }
            .confirmationDialog("Discard \(lines.count) food\(lines.count == 1 ? "" : "s")?",
                                isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Add to meal") { addEverything() }
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("Your cart hasn't been added to the meal yet.")
            }
        }
    }

    /// Running totals plus the one terminal action. Deliberately mirrors the
    /// Menu Checker cart's log bar: same place on screen, same read (what it
    /// adds up to on the left, the commit button on the right).
    private var addBar: some View {
        HStack {
            Button { showCart = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Formatters.kcal(totals.calories))
                        .font(.headline.weight(.bold))
                    Text("\(totals.itemCount) food\(totals.itemCount == 1 ? "" : "s") · Review")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button { addEverything() } label: {
                Label("Add \(totals.itemCount) to Meal", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func addEverything() {
        guard !lines.isEmpty else { return }
        onAdd(lines)
        dismiss()
    }
}

/// The cart itself: everything staged so far, with live totals, and per-food
/// edit / duplicate / remove. Pushed rather than presented so the amount sheet
/// can still come up over it, and so backing out returns to the food list with
/// the cart intact.
struct PresetCartReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var lines: [PresetCartLine]
    let onAdd: () -> Void
    @State private var editing: PresetCartLine?
    @State private var confirmClear = false

    private var totals: PresetCartTotals { PresetCartMath.totals(for: lines) }

    var body: some View {
        List {
            Section {
                LabeledContent("Calories", value: Formatters.kcal(totals.calories))
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    Text("\(Int(totals.protein.rounded()))P").foregroundStyle(.red)
                    Text("\(Int(totals.carbs.rounded()))C").foregroundStyle(.blue)
                    Text("\(Int(totals.fat.rounded()))F").foregroundStyle(.orange)
                    Spacer()
                    Text("\(Int(totals.fiber.rounded()))g fiber · \(Int(totals.sodium.rounded()))mg sodium")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
            } header: {
                Text("Cart total")
            } footer: {
                Text("Nothing is logged yet. These foods land in the meal's Foods list when you tap Add, and stay editable there.")
            }

            Section("Foods") {
                ForEach(lines) { line in
                    Button { editing = line } label: { row(line) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { remove(line) } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            Button { duplicate(line) } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
        .navigationTitle("Cart")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmClear = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Clear cart")
                .disabled(lines.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) { if !lines.isEmpty { addBar } }
        .sheet(item: $editing) { line in
            PresetAmountEntryView(preset: line.preset, initial: line.portion) { portion in
                guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
                lines[index].portion = portion
            }
        }
        .confirmationDialog("Clear the whole cart?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear cart", role: .destructive) { lines.removeAll() }
        }
        // An emptied cart has nothing left to review, so hand the user back to
        // the food list rather than leaving them on a blank screen.
        .onChange(of: lines.isEmpty) { if lines.isEmpty { dismiss() } }
    }

    private func row(_ line: PresetCartLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(line.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(Formatters.kcal(line.calories))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
            }
            HStack(spacing: 10) {
                Text(line.amountDescription).foregroundStyle(.secondary)
                if line.portion.weighed {
                    Label("Weighed", systemImage: "scalemass").foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(line.protein.rounded()))P").foregroundStyle(.red)
                Text("\(Int(line.carbs.rounded()))C").foregroundStyle(.blue)
                Text("\(Int(line.fat.rounded()))F").foregroundStyle(.orange)
            }
            .font(.caption.weight(.medium))
        }
        .contentShape(Rectangle())
    }

    private var addBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(Formatters.kcal(totals.calories)).font(.headline.weight(.bold))
                Text("\(totals.itemCount) food\(totals.itemCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { onAdd() } label: {
                Label("Add \(totals.itemCount) to Meal", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func remove(_ line: PresetCartLine) {
        lines.removeAll { $0.id == line.id }
    }

    /// A second helping of the same food at the same portion: one tap instead
    /// of finding the preset again and retyping the amount.
    private func duplicate(_ line: PresetCartLine) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines.insert(PresetCartLine(preset: line.preset, portion: line.portion), at: index + 1)
    }
}

/// Second step of picking a preset: say how much was eaten. Starts blank on
/// purpose when adding — a preset has no default portion, so the user always
/// types the actual amount instead of accepting a seeded number. Reopened from
/// a cart row it starts on what that row already says, so a portion can be
/// corrected without being retyped from scratch.
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

    private let isEditing: Bool
    @State private var mode: Mode
    @State private var servings: Double?
    @State private var grams: Double?
    @State private var weighed = false
    @FocusState private var amountFocused: Bool

    init(preset: FoodPreset, initial: PresetPortion? = nil,
         onConfirm: @escaping (PresetPortion) -> Void) {
        self.preset = preset
        self.onConfirm = onConfirm
        self.isEditing = initial != nil
        // Reopening a cart row restores the answer in the unit it was given
        // in: re-deriving grams from a "2 servings" answer would silently
        // change what the row means for a preset with no reference weight.
        if let initial, let servings = initial.servings {
            _mode = State(initialValue: .servings)
            _servings = State(initialValue: servings)
        } else if let initial {
            _mode = State(initialValue: .grams)
            _grams = State(initialValue: initial.grams)
            _weighed = State(initialValue: initial.weighed)
        } else {
            _mode = State(initialValue:
                preset.isCountedInServings || preset.effectiveReferenceGrams <= 0 ? .servings : .grams)
        }
    }

    private var referenceGrams: Double { preset.effectiveReferenceGrams }

    private var portion: PresetPortion? {
        switch mode {
        case .servings:
            guard let servings, servings > 0 else { return nil }
            return PresetPortion(grams: referenceGrams > 0 ? servings * referenceGrams : 0,
                                 ratio: servings, servings: servings)
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
                        LabeledContent(isEditing ? "Counts as" : "Adds") {
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
                        Text("Calories and macros are scaled from the preset's saved nutrition (per \(referenceGrams.formatted()) g). Turn on Weighed on a scale if the amount came off a food scale. Weighed items skip the Portion estimation adjustment.")
                    } else {
                        Text("This preset has no saved weight, so its nutrition is applied as-is regardless of the amount you enter. Switch to Servings, or set a Weight on the preset.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Amount" : "How Much?")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add to Cart") {
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
