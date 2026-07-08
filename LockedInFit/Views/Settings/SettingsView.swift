import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// Value-based routes for everything pushed in the Settings area. These
/// exist because `NavigationLink(destination:)` stores a fully-constructed
/// destination VIEW VALUE inside the link, rebuilt on every re-evaluation —
/// and on iOS 26 that fed a self-sustaining update cycle: push Goal (or any
/// integration page) and Self._printChanges showed SettingsView and the
/// child re-reporting "@self changed" in lockstep, hundreds of times per
/// second, freezing the app inside a single never-draining SwiftUI update.
/// The child's navigation-bar preferences re-trigger navigation resolution,
/// which reconstructs the eager destination values, which invalidates the
/// views again. With value-based links the link stores only this enum;
/// destinations are built lazily by navigationDestination(for:) in
/// DashboardView, exactly once per push, so there is no view value left to
/// churn.
enum SettingsRoute: Hashable {
    case settings
    case goalEdit
    case notifications
    case aiSettings
    case healthKitSync
    case looksSettings
    case socialClimber
    case googleCalendar
    case diagnostics
}

// Shared, file-scope fetch descriptors: never rebuilt per view init, so
// SwiftUI's attribute-graph equality check on the @Query configurations is
// trivially stable. See the matching comment in DashboardView.swift — a
// debugger pause showed the Settings freeze livelocked in exactly that
// comparison (Array<SortDescriptor>.== under AGGraphSetOutputValue).
private let settingsWeights = FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\BodyWeightEntry.date)])
private let settingsMeals = FetchDescriptor<MealLog>(sortBy: [SortDescriptor(\MealLog.date)])
private let settingsSteps = FetchDescriptor<StepEntry>(sortBy: [SortDescriptor(\StepEntry.date)])
private let settingsActiveGoals = FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.active })

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(settingsWeights) private var weights: [BodyWeightEntry]
    @Query(settingsMeals) private var meals: [MealLog]
    @Query(settingsSteps) private var steps: [StepEntry]
    @Query(settingsActiveGoals) private var activeGoals: [Goal]

    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importResult: String?
    @State private var weightInput = ""
    @State private var backupResult: String?
    @State private var confirmRestore = false
    @State private var isBackingUp = false
    /// Cached instead of calling BackupService.latestBackup() directly from
    /// the view body: that call decodes every backup file's full JSON
    /// snapshot from disk, and the body re-evaluates on every keystroke in
    /// any Settings field (live @Bindable bindings), which made typing
    /// anywhere in Settings re-decode all backups on every character.
    @State private var cachedLatestBackup: BackupService.BackupInfo?

    private var latestWeight: BodyWeightEntry? { weights.last }

    var body: some View {
        let _ = PerfLog.tick("SettingsView.body")
        // Prints which dependency (@Query, @State, environment, identity)
        // triggered each body re-evaluation — the render-loop detector
        // proves THIS body cycles endlessly; this names what drives it.
        let _ = Self._printChanges()
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
                NavigationLink(value: SettingsRoute.notifications) {
                    Label("Notifications", systemImage: "bell.badge")
                }
                NavigationLink(value: SettingsRoute.aiSettings) {
                    Label("AI Analysis", systemImage: "sparkles")
                }
                NavigationLink(value: SettingsRoute.healthKitSync) {
                    Label("Apple Health Sync", systemImage: "heart.fill")
                }
                NavigationLink(value: SettingsRoute.looksSettings) {
                    Label("Looks & Calendar", systemImage: "face.smiling")
                }
                NavigationLink(value: SettingsRoute.socialClimber) {
                    Label("Social Climber", systemImage: "person.2.wave.2")
                }
                #if DEBUG
                NavigationLink(value: SettingsRoute.diagnostics) {
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
                    BackupService.scheduleBackupSoon(container: context.container)
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
        .onChange(of: settingsList) { _, _ in
            BackupService.scheduleBackupSoon(container: context.container)
        }
        .onAppear {
            PerfLog.event("Settings.appear")
            if settingsList.isEmpty {
                context.insert(UserSettings())
            }
            if weightInput.isEmpty, let latestWeight {
                weightInput = String(format: "%.1f", latestWeight.weightKg)
            }
            cachedLatestBackup = BackupService.latestBackup()
        }
        .onDisappear {
            PerfLog.event("Settings.disappear")
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
            NavigationLink(value: SettingsRoute.goalEdit) {
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
                Task {
                    isBackingUp = true
                    let saved = await BackupService.backupNowManually(container: context.container) != nil
                    backupResult = saved ? "Backup saved just now." : "Nothing to back up, or a backup was already running."
                    cachedLatestBackup = BackupService.latestBackup()
                    isBackingUp = false
                }
            } label: {
                if isBackingUp {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Backing Up…")
                    }
                } else {
                    Label("Backup Now", systemImage: "externaldrive.badge.checkmark")
                }
            }
            .disabled(isBackingUp)
            if let latestBackup = cachedLatestBackup {
                Button {
                    confirmRestore = true
                } label: {
                    Label("Restore From Backup", systemImage: "clock.arrow.circlepath")
                }
                LabeledContent("Latest backup", value: Formatters.mediumDate(latestBackup.date))
                LabeledContent("Latest backup records", value: "\(latestBackup.recordCount)")
            } else {
                Text("No backups yet. Backups are also taken automatically as you use the app.")
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
        guard let latestBackup = cachedLatestBackup else { return }
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
