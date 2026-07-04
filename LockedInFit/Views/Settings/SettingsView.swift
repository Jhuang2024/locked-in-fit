import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]

    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importResult: String?

    var body: some View {
        Form {
            if let settings = settingsList.first {
                brandSection
                profileSection(settings)
                energySection(settings)
            }

            Section("Integrations") {
                NavigationLink(destination: AISettingsView()) {
                    Label("AI Meal Analysis", systemImage: "sparkles")
                }
                NavigationLink(destination: HealthKitSyncView()) {
                    Label("Apple Health Sync", systemImage: "heart.fill")
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
            Picker("Exercise calorie adjustment", selection: $settings.exerciseCalorieAdjustment) {
                ForEach(ExerciseCalorieAdjustment.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } header: {
            Text("Energy Model")
        } footer: {
            Text("Maintenance is estimated from BMR, steps, and activity, then adjusted over time using your logged intake and weight trend. Exercise adjustment controls how much active energy is added back to today's calorie target. Default is Conservative.")
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
