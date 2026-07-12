import SwiftUI
import SwiftData

/// The meal cart — a temporary, persistent list of what the user ate or plans to
/// eat. Grouped by restaurant, with per-item macros, live totals, combined
/// Health/Satiety, warnings, and confidence. Not a checkout: the terminal action
/// is "Log This Meal", which writes into the normal food history.
struct MealCartView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CartLine.addedAt) private var lines: [CartLine]
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]

    @State private var showLog = false
    @State private var showCustomFood = false
    @State private var confirmClear = false

    private var settings: UserSettings? { settingsList.first }
    private var profile: ScoringProfile {
        ScoringProfileBuilder.make(settings: settings, goal: goals.first, meals: meals)
    }
    private var summary: CartSummary { CartManager.summary(for: lines) }

    var body: some View {
        NavigationStack {
            Group {
                if lines.isEmpty {
                    EmptyStateView(systemImage: "cart",
                                   title: "Your cart is empty",
                                   message: "Add items from a restaurant menu, then log them all as one meal.")
                        .padding(.top, 60)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            totalsCard
                            ForEach(CartManager.groupedByRestaurant(lines), id: \.name) { group in
                                restaurantGroup(group.name, lines: group.lines)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 90)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Meal Cart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showCustomFood = true } label: { Label("Add custom food", systemImage: "plus") }
                        if !lines.isEmpty {
                            Button(role: .destructive) { confirmClear = true } label: { Label("Clear cart", systemImage: "trash") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .safeAreaInset(edge: .bottom) { if !lines.isEmpty { logBar } }
            .sheet(isPresented: $showLog) { LogCartView(lines: lines, summary: summary) { dismiss() } }
            .sheet(isPresented: $showCustomFood) { CustomFoodSheet() }
            .confirmationDialog("Clear the whole cart?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear cart", role: .destructive) { CartManager.clear(lines, context: context) }
            }
        }
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                HealthScoreGauge(score: summary.combinedHealthScore, size: 66)
                SatietyScoreGauge(score: summary.combinedSatietyScore, size: 66)
                VStack(alignment: .leading, spacing: 4) {
                    MacroReadout(nutrition: summary.nutrition)
                    ConfidenceDots(confidence: summary.confidence)
                }
                Spacer(minLength: 0)
            }
            ForEach(summary.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardBackground()
    }

    private func restaurantGroup(_ name: String, lines: [CartLine]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(name, systemImage: "storefront").font(.headline)
            ForEach(lines) { line in
                CartLineRow(line: line, profile: profile)
            }
        }
    }

    private var logBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(summary.nutrition.calories)) kcal").font(.headline.weight(.bold))
                Text("\(summary.itemCount) item\(summary.itemCount == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showLog = true } label: {
                Label("Log This Meal", systemImage: "checkmark.circle.fill")
                    .font(.headline).padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).background(.ultraThinMaterial)
    }
}

/// One editable cart line: name, modifications, per-line macros, a quantity
/// stepper, and swipe/menu actions (edit, duplicate, remove).
struct CartLineRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var line: CartLine
    let profile: ScoringProfile
    @State private var showEdit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.itemName).font(.subheadline.weight(.bold))
                    if !line.modificationSummary.isEmpty {
                        Text(line.modificationSummary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                NutritionSourceBadge(kind: line.sourceKind, compact: true)
            }
            HStack(spacing: 10) {
                Text("\(Int(line.lineNutrition.calories)) kcal").font(.system(.subheadline, design: .rounded, weight: .bold))
                Text("\(Int(line.lineNutrition.protein))P").foregroundStyle(.red).font(.caption.weight(.semibold))
                Text("\(Int(line.lineNutrition.carbs))C").foregroundStyle(.blue).font(.caption.weight(.semibold))
                Text("\(Int(line.lineNutrition.fat))F").foregroundStyle(.orange).font(.caption.weight(.semibold))
                Spacer()
                HealthChip(score: line.healthScore)
                SatietyChip(score: line.satietyScore)
            }
            HStack {
                Stepper(value: Binding(get: { line.quantity }, set: { CartManager.setQuantity(line, to: $0, context: context) }), in: 1...20) {
                    Text("Qty ×\(line.quantity)").font(.caption.weight(.semibold))
                }
                .fixedSize()
                Spacer()
                if line.spec != nil {
                    Button { showEdit = true } label: { Image(systemName: "slider.horizontal.3") }
                }
                Button { CartManager.duplicate(line, context: context) } label: { Image(systemName: "plus.square.on.square") }
                Button(role: .destructive) { CartManager.remove(line, context: context) } label: { Image(systemName: "trash") }
            }
            .font(.subheadline)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12).cardBackground()
        .sheet(isPresented: $showEdit) {
            if let spec = line.spec {
                NavigationStack {
                    MenuItemDetailView(item: spec.item, restaurantName: line.restaurantName, profile: profile,
                                       initialConfig: spec.config, editingLine: line)
                }
            }
        }
    }
}

/// Add a custom (non-restaurant) food alongside menu items.
struct CustomFoodSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var fiber = 0.0
    @State private var sodium = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") { TextField("Name", text: $name) }
                Section("Nutrition") {
                    field("Calories", $calories, "kcal")
                    field("Protein", $protein, "g")
                    field("Carbs", $carbs, "g")
                    field("Fat", $fat, "g")
                    field("Fiber", $fiber, "g")
                    field("Sodium", $sodium, "mg")
                }
            }
            .navigationTitle("Custom Food")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let n = ResolvedNutrition(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sodium: sodium)
                        let health = MenuHealthScoreCalculator.score(nutrition: n, components: [], sourceKind: .lowConfidenceEstimate).score
                        let satiety = SatietyScoreCalculator.score(nutrition: n, components: []).score
                        CartManager.addCustomFood(name: name.isEmpty ? "Custom food" : name, nutrition: n,
                                                  healthScore: health, satietyScore: satiety, context: context)
                        dismiss()
                    }
                    .disabled(calories <= 0)
                }
            }
        }
    }

    private func field(_ label: String, _ value: Binding<Double>, _ unit: String) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }
}
