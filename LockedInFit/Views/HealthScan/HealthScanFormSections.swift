import SwiftUI

/// Score/macro/ingredient fields shared between the review-before-save editor
/// and the saved-scan detail view, so both stay in sync as fields change.
struct HealthScanCoreSections: View {
    @Bindable var scan: HealthScan

    var body: some View {
        Section {
            HStack {
                Spacer()
                ScoreRingView(label: "Health Score", score: scan.healthScore, maxScore: 100, color: Self.scoreColor(scan.healthScore))
                Spacer()
                ScoreRingView(label: "Satiety Score", score: scan.satietyScore, maxScore: 100, color: Self.scoreColor(scan.satietyScore))
                Spacer()
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)

            Picker("Processing", selection: Binding(get: { scan.processedLevel }, set: { scan.processedLevel = $0 })) {
                ForEach(ProcessedLevel.allCases) { level in
                    Label(level.label, systemImage: level.systemImage).tag(level)
                }
            }
        }

        Section("Product") {
            TextField("Name", text: $scan.productName)
            TextField("Serving size", text: $scan.servingSize)
            DatePicker("Scanned", selection: $scan.date)
        }

        Section {
            HStack {
                StatChip(label: "kcal", value: "\(Int(scan.calories))")
                StatChip(label: "protein", value: "\(Int(scan.protein))g", color: .red)
                StatChip(label: "carbs", value: "\(Int(scan.carbs))g", color: .blue)
                StatChip(label: "fat", value: "\(Int(scan.fat))g", color: .yellow)
            }
            HStack {
                StatChip(label: "fiber", value: "\(Int(scan.fiber))g", color: .green)
                StatChip(label: "sugar", value: "\(Int(scan.sugar))g", color: .pink)
                StatChip(label: "sodium", value: "\(Int(scan.sodium))mg", color: .purple)
            }
            Text("\(String(format: "%.1f", scan.proteinPer100kcal)) g protein per 100 kcal")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Calories & Macros")
        }

        Section {
            field("Calories", value: $scan.calories, unit: "kcal")
            field("Protein", value: $scan.protein, unit: "g")
            field("Carbs", value: $scan.carbs, unit: "g")
            field("Fat", value: $scan.fat, unit: "g")
            field("Fiber", value: $scan.fiber, unit: "g")
            field("Sugar", value: $scan.sugar, unit: "g")
            field("Sodium", value: $scan.sodium, unit: "mg")
        } header: {
            Text("Edit Totals")
        }

        if !scan.concerningIngredients.isEmpty {
            Section("Potentially Concerning") {
                ForEach(scan.concerningIngredients, id: \.self) { ingredient in
                    Label(ingredient, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }

        if !scan.notes.isEmpty {
            Section("Notes") {
                Text(scan.notes)
                    .font(.subheadline)
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

    static func scoreColor(_ score: Double) -> Color {
        switch score {
        case ..<40: return .red
        case ..<70: return .orange
        default: return .green
        }
    }
}
