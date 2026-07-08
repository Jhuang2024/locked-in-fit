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
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]

    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importResult: String?
    @State private var weightInput = ""
    @State private var backupResult: String?
    @State private var confirmRestore = false

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

            goalSection

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
                NavigationLink(destination: SocialClimberLinkView()) {
                    Label("Social Climber", systemImage: "person.2.wave.2")
                }
                #if DEBUG
                NavigationLink(destination: DiagnosticsView()) {
                    Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                }
                #endif
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

            backupSection

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
        .confirmationDialog("Restore from the latest local backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore") { performRestore() }
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
            Picker("Exercise calorie adjustment", selection: $settings.exerciseCalorieAdjustment) {
                ForEach(ExerciseCalorieAdjustment.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Text(settings.exerciseCalorieAdjustment.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Energy Model")
        } footer: {
            Text("""
            Maintenance is estimated from BMR, steps, and activity, then adjusted over time using your logged intake and weight trend.

            Exercise calorie adjustment controls how much of today's estimated workout/step calories get added back to your target, useful because activity estimates run high:
            • Off: no calories added back; your target stays fixed regardless of activity.
            • Conservative (default): adds back 45%. Safest choice if you tend to overeat on training days.
            • Moderate: adds back 65%. A middle ground for reasonably accurate trackers.
            • Full: adds back 100%. Only use this if your activity data (e.g. a chest-strap HR monitor) is highly accurate.
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
        } header: {
            Text("Nutrition Limits")
        } footer: {
            Text("Sodium is treated as a stay-under target in the Dashboard and Food Log. Set this lower if your doctor gave you a specific limit.")
        }
    }

    /// Goal setup lives here now, not in Trends: the Goal Dashboard under
    /// Trends is read-only, a progress readout, not a place to change
    /// targets. This is the one place phase, target weight, and daily
    /// calorie/protein/step targets get set.
    private var goalSection: some View {
        Section("Goal") {
            NavigationLink(destination: GoalEditView(goal: activeGoals.first)) {
                Label(activeGoals.isEmpty ? "Set Up Goal" : "Edit Goal", systemImage: "target")
            }
            if let goal = activeGoals.first {
                LabeledContent("Phase", value: goal.phase.label)
                LabeledContent("Target weight", value: Formatters.kg(goal.targetWeightKg))
                LabeledContent("Daily calories", value: Formatters.kcal(goal.calorieTarget))
            }
        }
    }

    /// Local backups, separate from Export/Import above: those hand you a
    /// file to manage yourself, these are automatic snapshots LockedInFit
    /// keeps (and rotates) on-device so a bad migration or in-app mistake
    /// isn't the end of your data. They live inside the app's own sandbox,
    /// so they don't protect against a full uninstall; Export JSON, saved
    /// somewhere outside the app, is what survives that.
    private var backupSection: some View {
        Section {
            Button {
                if BackupService.backupNow(context: context) != nil {
                    backupResult = "Backup saved just now."
                } else {
                    backupResult = "Nothing to back up, or backup skipped to protect existing history."
                }
            } label: {
                Label("Backup Now", systemImage: "externaldrive.badge.checkmark")
            }
            if let latestBackup = BackupService.latestBackup() {
                Button {
                    confirmRestore = true
                } label: {
                    Label("Restore From Backup", systemImage: "clock.arrow.circlepath")
                }
                LabeledContent("Latest backup", value: Formatters.mediumDate(latestBackup.date))
                LabeledContent("Latest backup records", value: "\(latestBackup.recordCount)")
            } else {
                Text("No backups yet. Backups are also taken automatically, at most once a day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let backupResult {
                Text(backupResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Local Backups")
        } footer: {
            Text("Backups are separate from the export file above and live only on this device (up to the last \(BackupService.maxBackupsKept)). Restoring merges the backup's records back in without deleting anything currently on the device.")
        }
    }

    private func performRestore() {
        guard let latestBackup = BackupService.latestBackup() else { return }
        let currentCount = DataLossGuard.currentRecordCount(context: context)
        switch BackupService.restore(from: latestBackup, context: context, currentRecordCount: currentCount) {
        case .restored(let count):
            backupResult = "Restored \(count) records from the \(Formatters.mediumDate(latestBackup.date)) backup."
            DataLossGuard.acknowledge(context: context)
        case .emptyBackupSkipped:
            backupResult = "That backup is empty; nothing to restore."
        case .failed(let error):
            backupResult = "Restore failed: \(error.localizedDescription)"
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
