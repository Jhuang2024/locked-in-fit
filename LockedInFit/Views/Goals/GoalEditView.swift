import SwiftUI
import SwiftData

// Shared, file-scope fetch descriptors; see the comment in
// DashboardView.swift for why these must never be rebuilt per view init.
private let goalEditWeights = FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\BodyWeightEntry.date)])
private let goalEditMeals = FetchDescriptor<MealLog>(sortBy: [SortDescriptor(\MealLog.date)])
private let goalEditSteps = FetchDescriptor<StepEntry>(sortBy: [SortDescriptor(\StepEntry.date)])
private let goalEditActiveGoals = FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.active })

struct GoalEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(goalEditWeights) private var weights: [BodyWeightEntry]
    @Query(goalEditMeals) private var meals: [MealLog]
    @Query(goalEditSteps) private var steps: [StepEntry]
    @Query(goalEditActiveGoals) private var activeGoals: [Goal]
    @Query private var settingsList: [UserSettings]

    /// Queried here rather than passed in: this view is reached via the
    /// value-based SettingsRoute.goalEdit (no payload), so it looks up the
    /// active goal itself — same source of truth SettingsView's row uses.
    private var goal: Goal? { activeGoals.first }

    @State private var phase: GoalPhase = .cut
    @State private var targetWeight: Double = 75
    @State private var targetBodyFat: Double = 0
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: .now)!
    @State private var weeklyChange: Double = -0.4
    @State private var calorieTarget: Double = 2100
    @State private var proteinTarget: Double = 150
    @State private var stepTarget = 9000
    @State private var waistGoal: Double = 0

    private var currentWeight: Double {
        WeightTrendCalculator.currentTrendKg(entries: weights) ?? weights.last?.weightKg ?? 75
    }

    // No NavigationStack here, deliberately. This view used to be presented
    // as a sheet (where owning a stack is correct), but it is now PUSHED
    // from SettingsView inside the Today tab's NavigationStack — and a
    // nested NavigationStack inside a pushed destination made SwiftUI cycle
    // updates between parent and child forever on iOS 26: the render-loop
    // detector showed SettingsView.body and GoalEditView.body re-evaluating
    // in lockstep hundreds of times per second inside one blocked update,
    // freezing the whole app the moment this screen was pushed. The Form
    // hangs its title/toolbar on the enclosing stack's navigation bar, and
    // the back button is the cancel path (edits only commit in save()).
    var body: some View {
        Form {
                Section("Phase") {
                    Picker("Phase", selection: $phase) {
                        ForEach(GoalPhase.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: phase) {
                        weeklyChange = phase.defaultWeeklyChangeKg
                        applyRecommendations()
                    }
                }

                Section("Targets") {
                    numberField("Target weight", value: $targetWeight, unit: "kg")
                    numberField("Target body fat (0 = none)", value: $targetBodyFat, unit: "%")
                    Toggle("Target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Finish by", selection: $targetDate, displayedComponents: .date)
                    }
                    numberField("Weekly change", value: $weeklyChange, unit: "kg/wk")
                    numberField("Waist goal (0 = none)", value: $waistGoal, unit: "cm")
                }

                Section {
                    numberField("Calorie target", value: $calorieTarget, unit: "kcal")
                    numberField("Protein target", value: $proteinTarget, unit: "g")
                    Stepper("Step target: \(stepTarget)", value: $stepTarget, in: 3000...25000, step: 500)
                    Button("Auto-fill from maintenance estimate") { applyRecommendations() }
                } header: {
                    Text("Daily Targets")
                } footer: {
                    Text("Current trend weight: \(Formatters.kg(currentWeight)). Auto-fill uses your estimated maintenance and the weekly change target.")
                }
            }
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            // No keyboardDoneToolbar here while this view is pushed from
            // SettingsView: the parent Form registers its own keyboard
            // ToolbarItemGroup, and two keyboard accessory groups active in
            // the same navigation hierarchy are a suspect in the update
            // loop (the "Invalid frame dimension" layout warning is
            // keyboard-accessory-shaped). Form's interactive
            // scroll-to-dismiss still closes the numeric keyboard.
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                PerfLog.event("nav.goalEdit.appear")
                PerfLog.measure("goalEdit.load") { load() }
            }
    }

    private func numberField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }

    private func applyRecommendations() {
        guard let settings = settingsList.first else { return }
        let maintenance = Analytics.estimateMaintenance(settings: settings, weights: weights, meals: meals, steps: steps)
        calorieTarget = NutritionCalculator.calorieTarget(maintenance: maintenance, weeklyChangeKg: weeklyChange).rounded()
        proteinTarget = NutritionCalculator.proteinTarget(weightKg: currentWeight, phase: phase)
        stepTarget = phase == .cut ? 10000 : 8000
    }

    private func load() {
        guard let goal else {
            targetWeight = (currentWeight - 5).rounded()
            applyRecommendations()
            return
        }
        phase = goal.phase
        targetWeight = goal.targetWeightKg
        targetBodyFat = goal.targetBodyFatPercentage ?? 0
        hasTargetDate = goal.targetDate != nil
        if let date = goal.targetDate { targetDate = date }
        weeklyChange = goal.weeklyWeightChangeTarget
        calorieTarget = goal.calorieTarget
        proteinTarget = goal.proteinTarget
        stepTarget = goal.stepTarget
        waistGoal = goal.measurementGoals["waist"] ?? 0
    }

    private func save() {
        var measurementGoals: [String: Double] = [:]
        if waistGoal > 0 { measurementGoals["waist"] = waistGoal }

        if let goal {
            goal.phase = phase
            goal.targetWeightKg = targetWeight
            goal.targetBodyFatPercentage = targetBodyFat > 0 ? targetBodyFat : nil
            goal.targetDate = hasTargetDate ? targetDate : nil
            goal.weeklyWeightChangeTarget = weeklyChange
            goal.calorieTarget = calorieTarget
            goal.proteinTarget = proteinTarget
            goal.stepTarget = stepTarget
            goal.measurementGoals = measurementGoals
        } else {
            // Deactivate any lingering goals, then create the new active one.
            let all = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
            all.forEach { $0.active = false }
            context.insert(Goal(phase: phase, startDate: .now, startWeightKg: currentWeight,
                                targetWeightKg: targetWeight,
                                targetBodyFatPercentage: targetBodyFat > 0 ? targetBodyFat : nil,
                                targetDate: hasTargetDate ? targetDate : nil,
                                weeklyWeightChangeTarget: weeklyChange,
                                calorieTarget: calorieTarget, proteinTarget: proteinTarget,
                                stepTarget: stepTarget, measurementGoals: measurementGoals, active: true))
        }
        BackupService.scheduleBackupSoon(container: context.container)
        dismiss()
    }
}
