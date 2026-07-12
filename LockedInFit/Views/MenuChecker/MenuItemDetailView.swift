import SwiftUI
import SwiftData

/// Full menu-item screen: live nutrition, Health/Satiety breakdowns, oil and
/// portion controls, modifications, source & confidence, and add-to-cart. Every
/// control re-resolves the item immediately so the numbers and scores always
/// reflect the current configuration — the user can correct assumptions before
/// adding it.
struct MenuItemDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let restaurantName: String
    @State private var config: ItemConfiguration
    @State private var item: MenuItem
    @State private var showBreakdown = false
    @State private var customOilText = ""
    @State private var added = false
    let onAdded: (() -> Void)?
    /// When set, this screen edits an existing cart line in place instead of
    /// adding a new one.
    let editingLine: CartLine?

    @Query private var savedItems: [SavedMenuItemRecord]
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]

    // Profile is computed HERE from @Query, not passed in. Passing a
    // freshly-built ScoringProfile from the parent's navigationDestination
    // closure changed the closure every render, which made SwiftUI re-seed and
    // rebuild this destination on every frame — a livelock.
    private var profile: ScoringProfile {
        ScoringProfileBuilder.make(settings: settingsList.first, goal: goals.first, meals: meals)
    }

    init(item: MenuItem, restaurantName: String,
         initialConfig: ItemConfiguration = ItemConfiguration(),
         editingLine: CartLine? = nil, onAdded: (() -> Void)? = nil) {
        self.restaurantName = restaurantName
        self._item = State(initialValue: item)
        self._config = State(initialValue: initialConfig)
        self.editingLine = editingLine
        self.onAdded = onAdded
    }

    private var resolved: ResolvedMenuItem {
        MenuItemResolver.resolve(item: item, config: config, profile: profile)
    }
    private var isSaved: Bool { savedItems.contains { $0.itemID == item.id } }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                scoreStrip
                nutritionCard
                oilCard
                if !item.modifications.isEmpty { modificationsCard }
                quantityCard
                breakdownCard
                sourceCard
            }
            .padding(16)
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleSaved() } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { addBar }
        .keyboardDoneToolbar()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuItemPhoto(assetName: item.photoAssetName, height: 160)
            if !item.itemDescription.isEmpty {
                Text(item.itemDescription).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                NutritionSourceBadge(kind: resolved.sourceKind)
                if let price = MenuFormat.price(item.price, code: item.currencyCode) {
                    Text(price).font(.subheadline.weight(.semibold))
                }
                Spacer()
                ForEach(item.dietaryTags.prefix(2), id: \.self) { tag in
                    Label(tag.label, systemImage: tag.systemImage)
                        .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                }
            }
        }
    }

    private var scoreStrip: some View {
        HStack(spacing: 20) {
            HealthScoreGauge(score: resolved.healthScore)
            SatietyScoreGauge(score: resolved.satietyScore)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(resolved.healthReasons.prefix(2), id: \.self) { r in
                    Label(r, systemImage: "heart.fill").font(.caption2).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                }
                ForEach(resolved.satietyReasons.prefix(2), id: \.self) { r in
                    Label(r, systemImage: "gauge.with.dots.needle.bottom.50percent").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Nutrition · \(item.servingBasis.label)")
            MacroReadout(nutrition: resolved.perUnit)
            HStack(spacing: 16) {
                miniStat("Sodium", "\(Int(resolved.perUnit.sodium)) mg")
                if resolved.perUnit.oilCalories > 0 {
                    miniStat("Added oil", "\(Int(resolved.perUnit.oilCalories)) kcal")
                }
                miniStat("Per", "×\(config.effectiveQuantity) = \(Int(resolved.total.calories)) kcal")
            }
            ConfidenceDots(confidence: resolved.confidence)
            ForEach(resolved.dietaryWarnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardBackground()
    }

    // MARK: Oil

    private var oilCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Oil")
            Text("Cooking oil is estimated by method. Steamed and raw items get exactly zero added oil.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Oil", selection: oilBinding) {
                ForEach(OilLevel.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if (config.oilLevelOverride ?? item.defaultOilLevel) == .custom {
                HStack {
                    Text("Custom oil")
                    Spacer()
                    TextField("g", text: $customOilText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                        .onChange(of: customOilText) { _, new in
                            config.customOilGrams = Double(new)
                        }
                    Text("g").foregroundStyle(.secondary).font(.caption)
                }
            }
            Text(resolved.breakdown.oilDetail).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardBackground()
    }

    private var oilBinding: Binding<OilLevel> {
        Binding(
            get: { config.oilLevelOverride ?? item.defaultOilLevel },
            set: { config.oilLevelOverride = $0 })
    }

    // MARK: Modifications

    private var modificationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Modifications")
            ForEach(item.modifications) { mod in
                Button {
                    withAnimation(.snappy) { config.toggle(mod, in: item.modifications) }
                } label: {
                    HStack {
                        Image(systemName: config.selectedModificationIDs.contains(mod.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(config.selectedModificationIDs.contains(mod.id) ? .green : .secondary)
                        Text(mod.label)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.subheadline)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardBackground()
    }

    private var quantityCard: some View {
        HStack {
            SectionLabel(text: "Quantity")
            Spacer()
            Stepper(value: quantityBinding, in: 1...20) {
                Text("×\(config.effectiveQuantity)").font(.headline.monospacedDigit())
            }
            .fixedSize()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardBackground()
    }

    private var quantityBinding: Binding<Int> {
        Binding(get: { config.effectiveQuantity }, set: { config.quantity = $0 })
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { showBreakdown.toggle() } } label: {
                HStack {
                    SectionLabel(text: "Estimate breakdown")
                    Spacer()
                    Image(systemName: showBreakdown ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if showBreakdown {
                ForEach(Array(resolved.breakdown.componentLines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.label).font(.caption.weight(.semibold))
                            Text(line.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(line.calories)) kcal").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if resolved.breakdown.oilCalories > 0 {
                    Divider()
                    HStack {
                        Text("Added cooking oil").font(.caption.weight(.semibold))
                        Spacer()
                        Text("+\(Int(resolved.breakdown.oilCalories)) kcal").font(.caption.monospacedDigit()).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardBackground()
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Source")
            Text(sourceExplanation).font(.caption).foregroundStyle(.secondary)
            Text("Provided by \(restaurantName)").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardBackground()
    }

    private var sourceExplanation: String {
        switch resolved.sourceKind {
        case .official: return "These are the restaurant's official published nutrition facts, shown as-is."
        case .restaurantProvided: return "Derived from the restaurant's listed ingredients."
        case .estimatedFromIngredients: return "Estimated from the dish description, likely ingredients, cooking method, and a typical restaurant portion."
        case .lowConfidenceEstimate: return "A rough estimate — we had little to go on. Adjust the components if you know better."
        }
    }

    private var addBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(resolved.total.calories)) kcal").font(.headline.weight(.bold))
                Text("\(Int(resolved.total.protein))g protein").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if let editingLine {
                    CartManager.apply(resolved: resolved, to: editingLine)
                    try? context.save()
                } else {
                    CartManager.add(resolved, restaurantName: restaurantName, context: context)
                }
                added = true
                onAdded?()
                dismiss()
            } label: {
                Label(editingLine == nil ? (added ? "Added" : "Add to cart") : "Update item",
                      systemImage: added ? "checkmark" : (editingLine == nil ? "plus" : "checkmark.circle"))
                    .font(.headline).padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func toggleSaved() {
        if let existing = savedItems.first(where: { $0.itemID == item.id }) {
            context.delete(existing)
        } else {
            context.insert(SavedMenuItemRecord(item: item, restaurantName: restaurantName))
        }
        try? context.save()
    }
}

/// Placeholder-aware menu photo. Items without a photo get a tasteful gradient +
/// glyph rather than a broken image.
struct MenuItemPhoto: View {
    let assetName: String?
    var height: CGFloat = 120

    var body: some View {
        Group {
            if let assetName, UIImage(named: assetName) != nil {
                Image(assetName).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color.orange.opacity(0.25), Color.pink.opacity(0.18)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "fork.knife").font(.system(size: height * 0.24)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: height).frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
