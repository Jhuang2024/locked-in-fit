import Foundation
import SwiftData

/// One-time realistic sample data so the app is usable on first launch.
enum SeedDataService {

    static func seedIfNeeded(context: ModelContext) {
        let settings = fetchOrCreateSettings(context: context)
        guard !settings.seededSampleData else { return }
        settings.seededSampleData = true

        seedPresets(context: context)
        seedBodyData(context: context)
        seedMeals(context: context)
        seedWorkouts(context: context)
        seedGoal(context: context)
        seedMeasurements(context: context)
        context.insert(ProgressPhoto(date: Date().daysAgo(28), notes: "Start of cut. Photos not bundled — take your own from the Progress Photos screen."))

        try? context.save()

        // Compute initial strength scores from the seeded workouts.
        let workouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        let scores = (try? context.fetch(FetchDescriptor<StrengthScore>())) ?? []
        StrengthScoreCalculator.recompute(workouts: workouts, bodyWeightKg: 78, existing: scores, context: context)
        try? context.save()
    }

    static func fetchOrCreateSettings(context: ModelContext) -> UserSettings {
        if let existing = try? context.fetch(FetchDescriptor<UserSettings>()).first {
            return existing
        }
        let settings = UserSettings()
        context.insert(settings)
        return settings
    }

    // MARK: - Presets (China-friendly list)

    private static func seedPresets(context: ModelContext) {
        let presets: [FoodPreset] = [
            FoodPreset(name: "Stir-fried Eggplant", serving: "1 bowl (180 g)", calories: 260, protein: 4, carbs: 22, fat: 18, fiber: 6, sodium: 480, category: "Chinese Home-Cooked", notes: "Eggplant soaks up oil — real value can run 60–200 kcal higher.", cookingMethod: .stirFried),
            FoodPreset(name: "Stir-fried String Beans", serving: "1 bowl (150 g)", calories: 160, protein: 4, carbs: 12, fat: 11, fiber: 5, sodium: 420, category: "Chinese Home-Cooked", notes: "Often flash-fried first at restaurants.", cookingMethod: .stirFried),
            FoodPreset(name: "Stir-fried Leafy Greens", serving: "1 bowl (150 g)", calories: 110, protein: 3, carbs: 6, fat: 9, fiber: 3, sodium: 350, category: "Chinese Home-Cooked", notes: "Garlic + oil; moderate hidden oil.", cookingMethod: .stirFried),
            FoodPreset(name: "Winter Melon Soup", serving: "1 bowl (300 g)", calories: 90, protein: 4, carbs: 8, fat: 5, fiber: 2, sodium: 620, category: "Chinese Home-Cooked", notes: "Low oil unless made with pork bones.", cookingMethod: .soup),
            FoodPreset(name: "Bamboo Shoots (braised)", serving: "1 bowl (120 g)", calories: 110, protein: 3, carbs: 10, fat: 7, fiber: 4, sodium: 520, category: "Chinese Home-Cooked", notes: "Braised in oil + soy.", cookingMethod: .braised),
            FoodPreset(name: "Braised Tofu", serving: "1 bowl (180 g)", calories: 220, protein: 16, carbs: 8, fat: 14, fiber: 2, sodium: 560, category: "Chinese Home-Cooked", notes: "Medium oil risk; pan-fried first.", cookingMethod: .braised),
            FoodPreset(name: "Black Fungus Salad", serving: "1 plate (90 g)", calories: 70, protein: 2, carbs: 8, fat: 4, fiber: 3, sodium: 410, category: "Chinese Home-Cooked", notes: "Dressed with sesame oil.", cookingMethod: .raw),
            FoodPreset(name: "Boiled Shrimp", serving: "10 shrimp (100 g)", calories: 100, protein: 22, carbs: 0.5, fat: 1, fiber: 0, sodium: 300, category: "Protein", cookingMethod: .boiled),
            FoodPreset(name: "Braised Duck", serving: "1 plate (120 g)", calories: 320, protein: 22, carbs: 4, fat: 24, fiber: 0, sodium: 680, category: "Protein", notes: "Fatty; skin adds a lot.", cookingMethod: .braised),
            FoodPreset(name: "Lamb Slices (hot pot)", serving: "1 plate (100 g)", calories: 230, protein: 19, carbs: 0, fat: 17, fiber: 0, sodium: 90, category: "Protein", cookingMethod: .boiled),
            FoodPreset(name: "Stir-fried Pork Slices", serving: "1 plate (100 g)", calories: 230, protein: 18, carbs: 3, fat: 16, fiber: 0, sodium: 420, category: "Protein", cookingMethod: .stirFried),
            FoodPreset(name: "Braised Beef", serving: "1 plate (100 g)", calories: 250, protein: 26, carbs: 3, fat: 15, fiber: 0, sodium: 550, category: "Protein", cookingMethod: .braised),
            FoodPreset(name: "Noodles with Sauce", serving: "1 bowl (320 g)", calories: 520, protein: 16, carbs: 78, fat: 15, fiber: 4, sodium: 1100, category: "Staples", notes: "Sauce oil is the wildcard.", cookingMethod: .stirFried),
            FoodPreset(name: "Pork & Chive Dumplings", serving: "10 pcs (220 g)", calories: 420, protein: 18, carbs: 52, fat: 15, fiber: 3, sodium: 780, category: "Staples", cookingMethod: .boiled),
            FoodPreset(name: "Steamed White Rice", serving: "1 bowl (200 g)", calories: 260, protein: 5, carbs: 57, fat: 1, fiber: 1, sodium: 5, category: "Staples", cookingMethod: .steamed),
            FoodPreset(name: "Corn on the Cob", serving: "1 ear (150 g)", calories: 130, protein: 5, carbs: 27, fat: 2, fiber: 3, sodium: 20, category: "Staples", cookingMethod: .boiled),
            FoodPreset(name: "Boiled Eggs", serving: "2 eggs (100 g)", calories: 155, protein: 13, carbs: 1, fat: 11, fiber: 0, sodium: 125, category: "Protein", cookingMethod: .boiled),
            FoodPreset(name: "Quail Eggs", serving: "6 eggs (60 g)", calories: 95, protein: 8, carbs: 0.5, fat: 7, fiber: 0, sodium: 85, category: "Protein", cookingMethod: .boiled),
            FoodPreset(name: "Marinated Cucumber", serving: "1 plate (80 g)", calories: 45, protein: 1, carbs: 5, fat: 2.5, fiber: 1, sodium: 340, category: "Sides", cookingMethod: .raw),
            FoodPreset(name: "Seaweed Snack Pack", serving: "1 pack (5 g)", calories: 25, protein: 1, carbs: 1, fat: 2, fiber: 1, sodium: 90, category: "Snacks", cookingMethod: .raw),
            FoodPreset(name: "Grilled Chicken Breast", serving: "160 g", calories: 265, protein: 49, carbs: 0, fat: 6, fiber: 0, sodium: 380, category: "Protein", cookingMethod: .grilled),
            FoodPreset(name: "Baked Potato", serving: "1 medium (200 g)", calories: 190, protein: 4, carbs: 43, fat: 0.3, fiber: 4, sodium: 15, category: "Staples", cookingMethod: .baked),
            FoodPreset(name: "Protein Bar", serving: "1 bar (60 g)", calories: 210, protein: 20, carbs: 22, fat: 7, fiber: 3, sodium: 200, category: "Snacks", cookingMethod: .raw),
            FoodPreset(name: "Protein Ice Cream", serving: "1 tub (280 g)", calories: 330, protein: 28, carbs: 35, fat: 9, fiber: 5, sodium: 300, category: "Snacks", cookingMethod: .raw)
        ]
        presets.forEach { context.insert($0) }
    }

    // MARK: - Body data

    private static func seedBodyData(context: ModelContext) {
        var weight = 80.5
        for daysBack in stride(from: 60, through: 0, by: -1) {
            let date = Date().daysAgo(daysBack)
            weight -= 0.045 // slow cut
            let noise = Double.random(in: -0.6...0.6)
            context.insert(BodyWeightEntry(date: date, weightKg: ((weight + noise) * 10).rounded() / 10, source: .manual))
            if daysBack % 3 == 0 {
                let bf = 22.0 - Double(60 - daysBack) * 0.03 + Double.random(in: -0.5...0.5)
                context.insert(BodyFatEntry(date: date, bodyFatPercentage: (bf * 10).rounded() / 10, source: .manual))
            }
            context.insert(StepEntry(date: date.startOfDay, steps: Int.random(in: 5500...13000), source: .manual))
        }
    }

    // MARK: - Meals

    private static func seedMeals(context: ModelContext) {
        for daysBack in 0...13 {
            let day = Date().daysAgo(daysBack).startOfDay

            let breakfast = MealLog(
                date: Calendar.current.date(byAdding: .hour, value: 8, to: day)!,
                mealType: .breakfast, calories: 380, protein: 24, carbs: 42, fat: 13, fiber: 4, sodium: 320,
                confidence: 0.9, calorieLow: 350, calorieHigh: 430,
                notes: "Boiled eggs, corn, seaweed pack.",
                foodItems: [
                    FoodItem(name: "boiled eggs", grams: 100, calories: 155, protein: 13, carbs: 1, fat: 11, sodium: 125, cookingMethod: .boiled, confidence: 0.95),
                    FoodItem(name: "corn on the cob", grams: 150, calories: 130, protein: 5, carbs: 27, fat: 2, fiber: 3, sodium: 20, cookingMethod: .boiled, confidence: 0.9),
                    FoodItem(name: "seaweed snack + fruit", grams: 120, calories: 95, protein: 6, carbs: 14, fat: 0, fiber: 1, sodium: 175, cookingMethod: .raw, confidence: 0.8)
                ])
            context.insert(breakfast)

            let lunch = MealLog(
                date: Calendar.current.date(byAdding: .hour, value: 12, to: day)!,
                mealType: .lunch, calories: 620, protein: 38, carbs: 54, fat: 24, fiber: 8, sodium: 900,
                confidence: 0.68, calorieLow: 520, calorieHigh: 820,
                hiddenOilLow: 80, hiddenOilHigh: 260,
                notes: "Home-cooked Chinese. Estimate includes likely stir-fry oil.",
                foodItems: [
                    FoodItem(name: "stir-fried eggplant", grams: 180, calories: 260, protein: 4, carbs: 22, fat: 18, fiber: 6, sodium: 480, cookingMethod: .stirFried, confidence: 0.65),
                    FoodItem(name: "steamed white rice", grams: 200, calories: 260, protein: 5, carbs: 57, fat: 1, fiber: 1, sodium: 5, cookingMethod: .steamed, confidence: 0.9),
                    FoodItem(name: "boiled shrimp", grams: 100, calories: 100, protein: 22, carbs: 0.5, fat: 1, sodium: 300, cookingMethod: .boiled, confidence: 0.8)
                ])
            context.insert(lunch)

            let dinner = MealLog(
                date: Calendar.current.date(byAdding: .hour, value: 19, to: day)!,
                mealType: .dinner, calories: 560, protein: 42, carbs: 48, fat: 20, fiber: 6, sodium: 1050,
                confidence: 0.7, calorieLow: 480, calorieHigh: 700,
                hiddenOilLow: 40, hiddenOilHigh: 150,
                notes: "Dumplings, greens, winter melon soup.",
                foodItems: [
                    FoodItem(name: "pork & chive dumplings", grams: 220, calories: 420, protein: 18, carbs: 52, fat: 15, fiber: 3, sodium: 780, cookingMethod: .boiled, confidence: 0.75),
                    FoodItem(name: "stir-fried leafy greens", grams: 120, calories: 90, protein: 2, carbs: 5, fat: 7, fiber: 2, sodium: 280, cookingMethod: .stirFried, confidence: 0.6),
                    FoodItem(name: "winter melon soup", grams: 250, calories: 50, protein: 2, carbs: 5, fat: 2, fiber: 1, sodium: 500, cookingMethod: .soup, confidence: 0.7)
                ])
            context.insert(dinner)

            if daysBack % 2 == 0 {
                context.insert(MealLog(
                    date: Calendar.current.date(byAdding: .hour, value: 15, to: day)!,
                    mealType: .snack, calories: 210, protein: 20, carbs: 22, fat: 7, fiber: 3, sodium: 200,
                    confidence: 0.98, calorieLow: 200, calorieHigh: 220,
                    notes: "Protein bar.",
                    foodItems: [FoodItem(name: "protein bar", grams: 60, calories: 210, protein: 20, carbs: 22, fat: 7, fiber: 3, sodium: 200, cookingMethod: .raw, confidence: 0.98)]))
            }
        }
    }

    // MARK: - Workouts

    private static func seedWorkouts(context: ModelContext) {
        struct SeedExercise {
            let name: String; let pattern: MovementPattern; let equipment: Equipment
            let muscles: [MuscleGroup]; let baseWeight: Double; let reps: Int; let sets: Int
        }
        let upperA: [SeedExercise] = [
            .init(name: "Bench Press", pattern: .horizontalPush, equipment: .barbell, muscles: [.chest, .triceps], baseWeight: 80, reps: 5, sets: 4),
            .init(name: "Barbell Row", pattern: .horizontalPull, equipment: .barbell, muscles: [.back, .biceps], baseWeight: 70, reps: 8, sets: 4),
            .init(name: "Overhead Press", pattern: .verticalPush, equipment: .barbell, muscles: [.shoulders], baseWeight: 47.5, reps: 6, sets: 3),
            .init(name: "Lat Pulldown", pattern: .verticalPull, equipment: .cable, muscles: [.back, .biceps], baseWeight: 65, reps: 10, sets: 3)
        ]
        let lowerA: [SeedExercise] = [
            .init(name: "Back Squat", pattern: .squat, equipment: .barbell, muscles: [.quads, .glutes], baseWeight: 105, reps: 5, sets: 4),
            .init(name: "Romanian Deadlift", pattern: .hinge, equipment: .barbell, muscles: [.hamstrings, .glutes], baseWeight: 90, reps: 8, sets: 3),
            .init(name: "Leg Press", pattern: .squat, equipment: .machine, muscles: [.quads], baseWeight: 160, reps: 10, sets: 3),
            .init(name: "Hanging Leg Raise", pattern: .core, equipment: .bodyweight, muscles: [.core], baseWeight: 0, reps: 12, sets: 3)
        ]
        let deadliftDay: [SeedExercise] = [
            .init(name: "Deadlift", pattern: .hinge, equipment: .barbell, muscles: [.hamstrings, .glutes, .back], baseWeight: 140, reps: 3, sets: 4),
            .init(name: "Pull-Up", pattern: .verticalPull, equipment: .bodyweight, muscles: [.back, .biceps], baseWeight: 0, reps: 8, sets: 4),
            .init(name: "Dumbbell Bench Press", pattern: .horizontalPush, equipment: .dumbbell, muscles: [.chest], baseWeight: 30, reps: 10, sets: 3),
            .init(name: "Plank", pattern: .core, equipment: .bodyweight, muscles: [.core], baseWeight: 0, reps: 1, sets: 3)
        ]

        let schedule: [(daysBack: Int, title: String, type: WorkoutType, plan: [SeedExercise], progress: Double)] = [
            (2, "Upper A", .upperLower, upperA, 3), (4, "Lower A", .upperLower, lowerA, 3),
            (6, "Pull + Deadlift", .strength, deadliftDay, 2.5),
            (9, "Upper A", .upperLower, upperA, 2), (11, "Lower A", .upperLower, lowerA, 2),
            (13, "Pull + Deadlift", .strength, deadliftDay, 2.5),
            (16, "Upper A", .upperLower, upperA, 1), (18, "Lower A", .upperLower, lowerA, 1),
            (20, "Pull + Deadlift", .strength, deadliftDay, 0),
            (23, "Upper A", .upperLower, upperA, 0), (25, "Lower A", .upperLower, lowerA, 0),
            (27, "Pull + Deadlift", .strength, deadliftDay, -2.5)
        ]

        for entry in schedule {
            let workout = Workout(date: Date().daysAgo(entry.daysBack),
                                  title: entry.title, type: entry.type,
                                  duration: Double(Int.random(in: 55...75)),
                                  perceivedDifficulty: Int.random(in: 6...8), completed: true)
            for (index, seed) in entry.plan.enumerated() {
                let exercise = Exercise(name: seed.name, muscleGroups: seed.muscles,
                                        movementPattern: seed.pattern, equipment: seed.equipment,
                                        order: index, restSeconds: 150, targetRPE: 8)
                for setIndex in 0..<seed.sets {
                    let weight = seed.baseWeight > 0 ? seed.baseWeight + entry.progress : 0
                    let set = WorkoutSet(order: setIndex, reps: seed.reps, weight: weight,
                                         rpe: Double(Int.random(in: 7...9)), completed: true)
                    if seed.name == "Plank" { set.duration = 60; set.reps = 1 }
                    exercise.sets?.append(set)
                }
                workout.exercises?.append(exercise)
            }
            context.insert(workout)
        }

        // A reusable template.
        let template = Workout(date: Date().daysAgo(30), title: "Upper A (Template)", type: .upperLower, isTemplate: true)
        for (index, seed) in upperA.enumerated() {
            let exercise = Exercise(name: seed.name, muscleGroups: seed.muscles, movementPattern: seed.pattern,
                                    equipment: seed.equipment, order: index, restSeconds: 150, targetRPE: 8)
            for setIndex in 0..<seed.sets {
                exercise.sets?.append(WorkoutSet(order: setIndex, reps: seed.reps, weight: seed.baseWeight))
            }
            template.exercises?.append(exercise)
        }
        context.insert(template)
    }

    // MARK: - Goal & measurements

    private static func seedGoal(context: ModelContext) {
        context.insert(Goal(phase: .cut, startDate: Date().daysAgo(60), startWeightKg: 80.5,
                            targetWeightKg: 74, targetBodyFatPercentage: 15,
                            targetDate: Calendar.current.date(byAdding: .month, value: 3, to: .now),
                            weeklyWeightChangeTarget: -0.4, calorieTarget: 2050, proteinTarget: 165,
                            stepTarget: 10000, measurementGoals: ["waist": 80], active: true))
    }

    private static func seedMeasurements(context: ModelContext) {
        for (daysBack, waist) in [(56, 89.0), (42, 88.0), (28, 87.2), (14, 86.1), (2, 85.4)] {
            context.insert(MeasurementEntry(date: Date().daysAgo(daysBack), waist: waist,
                                            chest: 103 - Double(56 - daysBack) * 0.005,
                                            arms: 37.5, thighs: 60, shoulders: 120, neck: 39, hips: 98,
                                            notes: daysBack == 2 ? "Waist trending down nicely." : ""))
        }
    }
}
