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
    case backups
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
    @State private var isBackingUp = false
    /// Cached instead of calling BackupService.mostCompleteBackup()
    /// directly from the view body: that call touches disk (index +
    /// App Group mirror metadata), and the body re-evaluates on every
    /// keystroke in any Settings field (live @Bindable bindings), which
    /// made typing anywhere in Settings re-read backup state on every
    /// character. mostCompleteBackup(), not the newest-only
    /// BackupService.latestBackup(): a backup right before an update can be
    /// followed by a few more entries and a backgrounding-triggered backup
    /// that mirrors them to the App Group container, and if the local
    /// sandbox is then replaced, only that mirror survives — a newest-LOCAL
    /// stat would under-report what's actually safely backed up.
    @State private var cachedLatestBackup: BackupService.BackupInfo?
    /// The literal most recent backup by time, shown separately from
    /// cachedLatestBackup (which is actually the *most complete* one, by
    /// record count) — see BackupService.mostRecentBackup for why those
    /// two can disagree and both need their own row.
    @State private var cachedMostRecentBackup: BackupService.BackupInfo?
    /// Loaded once on appear, same reasoning as cachedLatestBackup above.
    /// Surfaces DataLossGuard's persisted incident log here — not gated to
    /// DEBUG — specifically so a data-loss event is visible from inside the
    /// app itself (with a timestamp and record counts) even on a build with
    /// no Mac/Xcode anywhere nearby when it happened.
    @State private var dataLossIncidents: [DataLossGuard.Incident] = []

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

            if !dataLossIncidents.isEmpty {
                dataSafetySection
            }

            Section {
                LabeledContent("Storage", value: "On-device only")
                LabeledContent("Version", value: "1.0")
            } footer: {
                Text("Locked In Fit is local-first. No accounts, no cloud, no analytics. The only network call is meal analysis via OpenRouter or BazaarLink when you enable it.")
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
            cachedLatestBackup = BackupService.mostCompleteBackup()
            cachedMostRecentBackup = BackupService.mostRecentBackup()
            dataLossIncidents = DataLossGuard.recentIncidents()
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

            Portion estimation trims your daily target by a percentage of your logged food, since portions are easy to underestimate. Pick how much you tend to underestimate by. It only affects calories, not your macro targets:
            • Off (default): trust your log exactly.
            • Conservative: 5%.
            • Moderate: 10%.
            • Full: 20%.
            """)
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
                    cachedLatestBackup = BackupService.mostCompleteBackup()
                    cachedMostRecentBackup = BackupService.mostRecentBackup()
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
            NavigationLink(value: SettingsRoute.backups) {
                Label("Restore From Backup", systemImage: "clock.arrow.circlepath")
            }
            if let mostRecentBackup = cachedMostRecentBackup {
                LabeledContent("Latest backup", value: Formatters.mediumDateTime(mostRecentBackup.date))
            }
            if let latestBackup = cachedLatestBackup {
                LabeledContent("Most complete backup", value: Formatters.mediumDateTime(latestBackup.date))
                LabeledContent("Most complete backup records", value: "\(latestBackup.recordCount)")
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
            Text("Backups are separate from the export file above: up to \(BackupService.maxBackupsKept) rotate on this device, the most complete one is never rotated out, and each backup is also mirrored to the shared App Group container so it survives app updates. Restoring merges records back in without deleting anything.")
        }
    }

    /// Only appears when DataLossGuard has actually recorded something —
    /// most people should never see this section. Each row is a moment the
    /// on-device record count suddenly dropped, either caught at launch or
    /// mid-session by the periodic watchdog (see RootTabView), so a report
    /// of "data deletes itself" has a timestamp and exact before/after
    /// counts attached instead of only a vague memory of when it happened.
    private var dataSafetySection: some View {
        Section {
            ForEach(dataLossIncidents) { incident in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(incident.kind == "mid-session" ? "While app was open" : "Detected at launch")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(Formatters.mediumDate(incident.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(incident.previousCount) → \(incident.currentCount) records")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let bytes = incident.storeFileSizeBytes {
                        Text(bytes > 100_000
                             ? "Store file was still \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) — the data may still be on disk."
                             : "Store file was \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)), consistent with an empty store.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Data Safety")
        } footer: {
            Text("LockedInFit detected the on-device record count drop suddenly at these times. If this keeps happening, use Restore From Backup above (pick the most-complete entry, not necessarily the newest) and consider saving an Export JSON file somewhere outside the app.")
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
