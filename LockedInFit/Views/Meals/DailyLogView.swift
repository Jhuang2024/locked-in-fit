import SwiftUI
import SwiftData

/// Day-by-day food log with running totals.
struct DailyLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealLog.date) private var allMeals: [MealLog]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]
    @Query private var settingsList: [UserSettings]

    @State private var selectedDate = Date().startOfDay
    @State private var showAddMeal = false
    @State private var showPhotoAnalysis = false

    private var dayMeals: [MealLog] {
        allMeals.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }
    private var sodiumLimit: Double { max(1, settingsList.first?.sodiumLimitMg ?? 2300) }
    private var totals: (kcal: Double, p: Double, c: Double, f: Double, fiber: Double, sodium: Double, oilLow: Double, oilHigh: Double) {
        dayMeals.reduce((0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)) {
            ($0.0 + $1.calories, $0.1 + $1.protein, $0.2 + $1.carbs, $0.3 + $1.fat,
             $0.4 + $1.fiber, $0.5 + $1.sodium, $0.6 + $1.hiddenOilLow, $0.7 + $1.hiddenOilHigh)
        }
    }

    var body: some View {
        List {
            Section {
                DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }

            Section("Totals") {
                let t = totals
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatChip(label: "kcal", value: "\(Int(t.kcal))")
                        StatChip(label: "protein", value: "\(Int(t.p))g", color: .red)
                        StatChip(label: "carbs", value: "\(Int(t.c))g", color: .blue)
                        StatChip(label: "fat", value: "\(Int(t.f))g", color: .yellow)
                    }
                    HStack {
                        StatChip(label: "fiber", value: "\(Int(t.fiber))g", color: .green)
                        StatChip(label: "sodium", value: "\(Int(t.sodium))mg", color: sodiumColor(for: t.sodium))
                        if let goal = goals.first {
                            StatChip(label: "vs target", value: "\(Int(t.kcal - goal.calorieTarget))",
                                     color: t.kcal > goal.calorieTarget ? .red : .green)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sodium limit")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(t.sodium)) / \(Int(sodiumLimit)) mg")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(sodiumColor(for: t.sodium))
                        }
                        ProgressView(value: min(t.sodium, sodiumLimit), total: sodiumLimit)
                            .tint(sodiumColor(for: t.sodium))
                    }
                    if t.oilHigh > 0 {
                        Label("Hidden oil uncertainty: +\(Int(t.oilLow)) to +\(Int(t.oilHigh)) kcal", systemImage: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    let tef = NutritionCalculator.tef(protein: t.p, carbs: t.c, fat: t.f)
                    if tef > 10 {
                        Text("TEF ≈ \(Int(tef)) kcal burned digesting (net intake ~\(Int(t.kcal - tef)))")
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
