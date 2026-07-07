import SwiftUI
import SwiftData

/// Day-by-day food log with running totals. The calorie summary comes from
/// the same DashboardViewModel math as the Today dashboard (hidden oil, TEF,
/// exercise adjustment), so the two screens can never disagree.
struct DailyLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealLog.date) private var allMeals: [MealLog]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]
    @Query private var settingsList: [UserSettings]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \StepEntry.date, order: .reverse) private var steps: [StepEntry]
    @Query(sort: \ActiveEnergyEntry.date, order: .reverse) private var activeEnergy: [ActiveEnergyEntry]
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }) private var completedWorkouts: [Workout]

    @State private var selectedDate = Date().startOfDay
    @State private var showAddMeal = false
    @State private var showPhotoAnalysis = false

    private var dayMeals: [MealLog] {
        allMeals.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }
    private var sodiumLimit: Double { max(1, settingsList.first?.sodiumLimitMg ?? 2300) }
    /// Shared source of truth with the dashboard, evaluated for the selected day.
    private var dayModel: DashboardViewModel {
        DashboardViewModel(settings: settingsList.first,
                           goal: goals.first,
                           meals: allMeals,
                           weights: weights,
                           steps: steps,
                           activeEnergy: activeEnergy,
                           workouts: completedWorkouts,
                           date: selectedDate)
    }

    var body: some View {
        List {
            Section {
                DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }

            Section("Totals") {
                let model = dayModel
                let nutrition = model.nutrition
                let calories = model.calories
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatChip(label: "kcal", value: "\(Int(nutrition.calories))")
                        StatChip(label: "protein", value: "\(Int(nutrition.protein))g", color: .red)
                        StatChip(label: "carbs", value: "\(Int(nutrition.carbs))g", color: .blue)
                        StatChip(label: "fat", value: "\(Int(nutrition.fat))g", color: .yellow)
                    }
                    HStack {
                        StatChip(label: "fiber", value: "\(Int(nutrition.fiber))g", color: .green)
                        StatChip(label: "sodium", value: "\(Int(nutrition.sodium))mg", color: sodiumColor(for: nutrition.sodium))
                    }
                    HStack {
                        StatChip(label: "Eaten", value: "\(Int(calories.eaten))")
                        StatChip(label: "Target", value: "\(Int(calories.adjustedTarget))")
                        StatChip(label: "Remaining", value: "\(Int(calories.remaining))",
                                 color: calories.remaining < 0 ? .red : .green)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sodium limit")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(nutrition.sodium)) / \(Int(sodiumLimit)) mg")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(sodiumColor(for: nutrition.sodium))
                        }
                        ProgressView(value: min(nutrition.sodium, sodiumLimit), total: sodiumLimit)
                            .tint(sodiumColor(for: nutrition.sodium))
                    }
                    if nutrition.hiddenOilHigh > 0 {
                        Label("Hidden oil adds +\(Int(calories.hiddenOilCalories)) kcal to eaten (range +\(Int(nutrition.hiddenOilLow))–\(Int(nutrition.hiddenOilHigh)))", systemImage: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if calories.tefCalories > 0 {
                        Text("TEF adds +\(Int(calories.tefCalories)) kcal to the day's target (burned digesting).")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                    if calories.exerciseAdjustment > 0 {
                        Text("Exercise adds +\(Int(calories.exerciseAdjustment)) kcal to the day's target.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Meals") {
                if dayMeals.isEmpty {
                    Text("No meals logged this day.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(MealType.allCases) { type in
                        let mealsOfType = dayMeals.filter { $0.mealType == type }
                        ForEach(mealsOfType) { meal in
                            NavigationLink(destination: MealDetailView(meal: meal)) {
                                MealRowView(meal: meal)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                ImageStore.delete(mealsOfType[index].photoPath)
                                context.delete(mealsOfType[index])
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink(destination: HealthScanListView()) {
                    Label("Health Scans", systemImage: "text.magnifyingglass")
                }
                NavigationLink(destination: FoodPresetsView()) {
                    Label("Food Presets", systemImage: "list.star")
                }
            }
        }
        .navigationTitle("Food Log")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showPhotoAnalysis = true } label: { Image(systemName: "camera") }
                Button { showAddMeal = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddMeal) { AddMealView() }
        .sheet(isPresented: $showPhotoAnalysis) { MealPhotoAnalysisView() }
    }

    private func sodiumColor(for sodium: Double) -> Color {
        let ratio = sodium / sodiumLimit
        if ratio > 1 { return .red }
        if ratio >= 0.8 { return .orange }
        return .green
    }
}
