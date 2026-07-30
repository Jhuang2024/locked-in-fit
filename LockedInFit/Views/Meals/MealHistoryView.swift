import SwiftUI
import SwiftData

/// What you ate on the days before this one: a day-by-day list of every meal
/// logged, with that day's calories and macros scored against the same target
/// the dashboard used at the time.
///
/// The Food Log can already be pointed at any single date, but that only
/// answers "what did I eat on this exact day" one day at a time, and only if
/// you already know which day you're looking for. This is the readable
/// history: scroll back through yesterday, the day before, last week, see
/// where the calories landed each day, and open any meal to edit it.
struct MealHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]
    @Query private var settingsList: [UserSettings]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \StepEntry.date, order: .reverse) private var steps: [StepEntry]
    @Query(sort: \ActiveEnergyEntry.date, order: .reverse) private var activeEnergy: [ActiveEnergyEntry]
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }) private var completedWorkouts: [Workout]

    /// Set by the Food Log so a day can be opened there; nil when history is
    /// reached from somewhere with no day view to jump to (Trends), where the
    /// jump affordance is simply hidden rather than shown doing nothing.
    var onOpenDay: ((Date) -> Void)? = nil

    @State private var windowDays: Int = 14

    /// Matches the trend screens' window control; `allTime` reaches back to
    /// the first meal ever logged.
    private static let allTime = Int.max

    private var days: [DayFoodSummary] {
        MealHistoryCalculator.summaries(
            meals: meals,
            goal: goals.first,
            settings: settingsList.first,
            weights: weights,
            steps: steps,
            activeEnergy: activeEnergy,
            workouts: completedWorkouts,
            days: windowDays == Self.allTime ? nil : windowDays)
    }

    var body: some View {
        List {
            Section {
                Picker("Window", selection: $windowDays) {
                    Text("2W").tag(14)
                    Text("1M").tag(30)
                    Text("3M").tag(90)
                    Text("All").tag(Self.allTime)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            let history = days
            if let averages = MealHistoryCalculator.averages(history) {
                Section("Average per logged day") {
                    HStack {
                        StatChip(label: "days logged", value: "\(averages.loggedDays)", color: .teal)
                        StatChip(label: "kcal", value: "\(Int(averages.calories))", color: .accentColor)
                        StatChip(label: "protein", value: "\(Int(averages.protein))g", color: .red)
                    }
                    .padding(.vertical, 4)
                }
            }

            if history.isEmpty {
                Section {
                    Text("No meals logged yet. Anything you log shows up here, day by day.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(history) { day in
                Section {
                    if day.isEmpty {
                        Text("Nothing logged")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        daySummaryRow(day)
                        ForEach(day.meals) { meal in
                            NavigationLink(destination: MealDetailView(meal: meal)) {
                                MealRowView(meal: meal)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(Formatters.dayLabel(day.date))
                        Spacer()
                        Text(Formatters.mediumDate(day.date))
                            .foregroundStyle(.secondary)
                    }
                    // "Yesterday" reads as a date, not a shouted column
                    // heading, so the default uppercasing is dropped here.
                    .textCase(nil)
                }
            }
        }
        .navigationTitle("Meal History")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The day's headline numbers. Tappable when there's a Food Log to send
    /// back to that date, so "what was this day?" leads straight into editing
    /// it rather than dead-ending on a summary.
    @ViewBuilder
    private func daySummaryRow(_ day: DayFoodSummary) -> some View {
        if let onOpenDay {
            Button {
                onOpenDay(day.date)
                dismiss()
            } label: {
                HStack {
                    dayTotals(day)
                    Image(systemName: "arrow.forward.circle")
                        .foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)
        } else {
            dayTotals(day)
        }
    }

    private func dayTotals(_ day: DayFoodSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(day.calories.eaten))")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                Text("kcal of \(Int(day.calories.adjustedTarget)) target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(day.remaining < 0
                     ? "\(Int(-day.remaining)) over"
                     : "\(Int(day.remaining)) left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(day.remaining < 0 ? .red : .green)
            }
            Text(macroLine(day))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func macroLine(_ day: DayFoodSummary) -> String {
        let nutrition = day.nutrition
        var parts = ["P \(Int(nutrition.protein))g",
                     "C \(Int(nutrition.carbs))g",
                     "F \(Int(nutrition.fat))g",
                     day.meals.count == 1 ? "1 meal" : "\(day.meals.count) meals"]
        if nutrition.hiddenOilCalories > 0 {
            parts.append("oil ~\(Int(nutrition.hiddenOilCalories)) kcal")
        }
        return parts.joined(separator: " · ")
    }
}
