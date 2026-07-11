import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \MealLog.date) private var meals: [MealLog]
    @Query(sort: \StepEntry.date) private var steps: [StepEntry]

    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importResult: String?
    @State private var weightInput = ""

    private var latestWeight: BodyWeightEntry? { weights.last }

    var body: some View {
        Form {
            if let settings = settingsList.first {
                brandSection
                profileSection(settings)
                weightSection(settings)
                energySection(settings)
                nutritionSection(settings)
            }

            Section("Integrations") {
                NavigationLink(destination: NotificationSettingsView()) {
                    Label("Notifications", systemImage: "bell.badge")
                }
                NavigationLink(destination: AISettingsView()) {
                    Label("AI Analysis", systemImage: "sparkles")
                }
                NavigationLink(destination: HealthKitSyncView()) {
                    Label("Apple Health Sync", systemImage: "heart.fill")
                }
                NavigationLink(destination: LooksSettingsView()) {
                    Label("Looks & Calendar", systemImage: "face.smiling")
                }
            }

            Section("Data") {
                Button {
                    exportURL = try? ExportImportService.exportJSON(context: context)
                } label: {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                }
                Button {
                    exportURL = try? ExportImportService.exportCSV(context: context)
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import JSON", systemImage: "square.and.arrow.down")
                }
                if let importResult {
                    Text(importResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Storage", value: "On-device only")
                LabeledContent("Version", value: "1.0")
            } footer: {
                Text("Locked In Fit is local-first. No accounts, no cloud, no analytics. The only network call is meal analysis via OpenRouter when you enable it.")
            }
        }
        .navigationTitle("Settings")
        .keyboardDoneToolbar()
        .sheet(item: Binding(
            get: { exportURL.map { ShareItem(url: $0) } },
            set: { _ in exportURL = nil })) { item in
            ShareSheet(url: item.url)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let count = try ExportImportService.importJSON(from: url, context: context)
                    importResult = "Imported \(count) records."
                } catch {
                    importResult = "Import failed: \(error.localizedDescription)"
                }
            case .failure(let error):
                importResult = "Import failed: \(error.localizedDescription)"
            }
        }
        .onAppear {
            if settingsList.isEmpty {
                context.insert(UserSettings())
            }
            if weightInput.isEmpty, let latestWeight {
                weightInput = String(format: "%.1f", latestWeight.weightKg)
            }
        }
    }

    private var brandSection: some View {
        Section {
            HStack(spacing: 12) {
                AppBrandMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Locked In Fit")
                        .font(.headline)
                    Text("Local-first training and nutrition")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func profileSection(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Section("Profile") {
            HStack {
                Text("Height")
                Spacer()
                TextField("cm", value: $settings.heightCm, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("cm").font(.caption).foregroundStyle(.secondary)
            }
            Stepper("Age: \(settings.age)", value: $settings.age, in: 13...100)
            Picker("Sex", selection: $settings.sex) {
                ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
            }
            Picker("Units", selection: $settings.units) {
                ForEach(UnitSystem.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    private func weightSection(_ settings: UserSettings) -> some View {
        Section {
            HStack {
                Text("Current weight")
                Spacer()
                TextField("kg", text: $weightInput)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onSubmit { saveWeight() }
                Text("kg").font(.caption).foregroundStyle(.secondary)
            }
            if let latestWeight {
                LabeledContent("Last logged", value: Formatters.mediumDate(latestWeight.date))
            }
            LabeledContent("Estimated maintenance", value: Formatters.kcal(estimatedMaintenance(settings)))
        } header: {
            Text("Body")
        } footer: {
            Text("Your current weight drives the maintenance estimate, exercise calorie adjustment, and every calorie/protein/step target derived from it. Update it here whenever it changes, with no need to visit Weight Trends just to log a number.")
        }
        .onChange(of: weightInput) { saveWeight() }
    }

    private func estimatedMaintenance(_ settings: UserSettings) -> Double {
        Analytics.estimateMaintenance(settings: settings, weights: weights, meals: meals, steps: steps)
    }

    private func saveWeight() {
        guard let kg = Double(weightInput), kg > 20, kg < 300 else { return }
        if let latestWeight, latestWeight.date.isToday {
            latestWeight.weightKg = kg
        } else {
            context.insert(BodyWeightEntry(date: .now, weightKg: kg, source: .manual))
        }
        Task { await HealthKitManager.shared.writeWeight(kg, date: .now) }
    }

    private func energySection(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            Picker("Non-step activity", selection: $settings.activityAssumption) {
                ForEach(ActivityAssumption.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Account for TEF", isOn: $settings.applyTEF)
            HStack {
                Text("Manual maintenance (0 = auto)")
                Spacer()
                TextField("kcal", value: $settings.manualMaintenanceOverride, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        } header: {
            Text("Energy Model")
        } footer: {
            Text("""
            Maintenance is estimated from BMR, steps, and activity, then adjusted over time using your logged intake and weight trend.

            Tracked workout and step calories are credited to your target in full. To hedge against inaccuracy, use the Portion estimation setting under Nutrition rather than discounting your activity.
            """)
        }
    }

    private func nutritionSection(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            HStack {
                Text("Daily sodium limit")
                Spacer()
                TextField("mg", value: $settings.sodiumLimitMg, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("mg").font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Default guidance", value: "2300 mg/day")
            Picker("Portion estimation", selection: $settings.portionEstimationAdjustment) {
                ForEach(PortionEstimationAdjustment.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Text(settings.portionEstimationAdjustment.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Nutrition Limits")
        } footer: {
            Text("""
            Sodium is treated as a stay-under target in the Dashboard and Food Log. Set this lower if your doctor gave you a specific limit.

            Portion estimation adds a percentage on top of your logged food calories, since portions are easy to underestimate. It only inflates calories, not your macro targets:
            • Off: trust your log exactly.
            • Conservative (default): +5%.
            • Moderate: +10%.
            • Full: +20%.
            """)
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
