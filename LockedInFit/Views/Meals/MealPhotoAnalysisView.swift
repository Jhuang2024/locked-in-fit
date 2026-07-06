import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Photo → AI/mock estimate → editable review → save.
struct MealPhotoAnalysisView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    @State private var model = MealAnalysisViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var draft: MealLog?

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    MealDraftEditor(meal: draft, providerUsed: model.providerUsed) {
                        context.insert(draft)
                        dismiss()
                    }
                } else {
                    setupAndAnalyze
                }
            }
            .navigationTitle("Meal Photo")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var setupAndAnalyze: some View {
        Form {
            Section {
                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                HStack {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Library", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            }

            Section("Context") {
                Picker("Meal", selection: $model.mealType) {
                    ForEach(MealType.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Home-cooked meal", isOn: $model.isHomeCooked)
                TextField("Describe the meal (optional)", text: $model.userDescription, axis: .vertical)
            }

            Section {
                switch model.phase {
                case .analyzing:
                    HStack {
                        ProgressView()
                        Text("Analyzing with \(model.providerUsed)…")
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 10) {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                        HStack {
                            Button("Retry") {
                                Task { await runAnalysis(forceMock: false) }
                            }
                            .buttonStyle(.bordered)
                            Button("Use mock estimate") {
                                Task { await runAnalysis(forceMock: true) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                default:
                    Button {
                        Task { await runAnalysis(forceMock: false) }
                    } label: {
                        Label("Analyze Photo", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.image == nil)
                }
            } footer: {
                let mode = AIMode(rawValue: settings?.aiModeRaw ?? "mock") ?? .mock
                if mode == .openRouter && KeychainService.openRouterAPIKey != nil {
                    Text("Using OpenRouter (\(settings?.aiModelName ?? "")). Nothing is saved until you review the estimate.")
                } else {
                    Text("Mock mode: realistic offline estimates. Add an OpenRouter key in Settings → AI Analysis for real photo analysis.")
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                model.image = image
                model.phase = .ready
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) {
            Task {
                if let data = try? await photoItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    model.image = image
                    model.phase = .ready
                }
            }
        }
    }

    private func runAnalysis(forceMock: Bool) async {
        await model.analyze(settings: settings, forceMock: forceMock)
        if case .reviewing = model.phase {
            draft = model.makeDraft()
        }
    }
}

/// Editable estimate review. The meal is NOT saved until the user confirms.
struct MealDraftEditor: View {
    @Bindable var meal: MealLog
    let providerUsed: String
    let onSave: () -> Void

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(meal.honestSummary)
                        .font(.callout.weight(.semibold))
                    HStack {
                        ConfidenceBadge(confidence: meal.confidence)
                        Text("via \(providerUsed)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !meal.notes.isEmpty {
                        Text(meal.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Meal") {
                Picker("Type", selection: Binding(get: { meal.mealType }, set: { meal.mealType = $0 })) {
                    ForEach(MealType.allCases) { Text($0.label).tag($0) }
                }
                DatePicker("Time", selection: Binding(get: { meal.date }, set: { meal.date = $0 }))
            }

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

            Section("Totals (editable)") {
                totalField("Calories", value: Binding(get: { meal.calories }, set: { meal.calories = $0 }), unit: "kcal")
                totalField("Protein", value: Binding(get: { meal.protein }, set: { meal.protein = $0 }), unit: "g")
                totalField("Carbs", value: Binding(get: { meal.carbs }, set: { meal.carbs = $0 }), unit: "g")
                totalField("Fat", value: Binding(get: { meal.fat }, set: { meal.fat = $0 }), unit: "g")
                totalField("Fiber", value: Binding(get: { meal.fiber }, set: { meal.fiber = $0 }), unit: "g")
                totalField("Sodium", value: Binding(get: { meal.sodium }, set: { meal.sodium = $0 }), unit: "mg")
            }

            Section {
                Button {
                    onSave()
                } label: {
                    Label("Save Meal", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func totalField(_ label: String, value: Binding<Double>, unit: String) -> some View {
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
}

struct FoodItemEditorRow: View {
    @Bindable var item: FoodItem
    var onChanged: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Name", text: $item.name)
                    .font(.subheadline.weight(.medium))
                ConfidenceBadge(confidence: item.confidence)
            }
            HStack(spacing: 8) {
                amountField("g")
                labeledField("kcal", value: nutrientBinding(\.calories))
                labeledField("P", value: nutrientBinding(\.protein))
                labeledField("C", value: nutrientBinding(\.carbs))
                labeledField("F", value: nutrientBinding(\.fat))
            }
            HStack {
                Picker("", selection: Binding(get: { item.cookingMethod }, set: { item.cookingMethod = $0; onChanged() })) {
                    ForEach(CookingMethod.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .font(.caption)
                Spacer()
                Text(HiddenOilEstimator.riskLabel(for: item.cookingMethod))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func amountField(_ label: String) -> some View {
        labeledField(label, value: Binding(
            get: { item.grams },
            set: { newValue in
                let oldValue = item.grams
                item.grams = newValue
                if oldValue > 0, newValue > 0, oldValue != newValue {
                    let ratio = newValue / oldValue
                    item.calories *= ratio
                    item.protein *= ratio
                    item.carbs *= ratio
                    item.fat *= ratio
                    item.fiber *= ratio
                    item.sodium *= ratio
                }
                onChanged()
            }
        ))
    }

    private func nutrientBinding(_ keyPath: ReferenceWritableKeyPath<FoodItem, Double>) -> Binding<Double> {
        Binding(
            get: { item[keyPath: keyPath] },
            set: { newValue in
                item[keyPath: keyPath] = newValue
                onChanged()
            }
        )
    }

    private func labeledField(_ label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.callout)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        Text("\(Int(confidence * 100))% sure")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch confidence {
        case ..<0.5: return .red
        case ..<0.75: return .orange
        default: return .green
        }
    }
}
