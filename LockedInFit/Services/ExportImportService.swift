import Foundation
import SwiftData

/// Local JSON/CSV export and JSON import. No cloud anything.
enum ExportImportService {

    // MARK: - Codable snapshot

    struct Snapshot: Codable {
        var exportedAt: Date = .now
        var meals: [MealDTO] = []
        var presets: [PresetDTO] = []
        var weights: [WeightDTO] = []
        var bodyFats: [BodyFatDTO] = []
        var measurements: [MeasurementDTO] = []
        var steps: [StepDTO] = []
        var goals: [GoalDTO] = []
        var workouts: [WorkoutDTO] = []
    }

    struct MealDTO: Codable {
        var date: Date; var mealType: String; var calories: Double; var protein: Double
        var carbs: Double; var fat: Double; var fiber: Double; var sodium: Double
        var confidence: Double; var calorieLow: Double; var calorieHigh: Double
        var hiddenOilLow: Double; var hiddenOilHigh: Double; var notes: String
        var foodItems: [ItemDTO]

        struct ItemDTO: Codable {
            var name: String; var grams: Double; var calories: Double; var protein: Double
            var carbs: Double; var fat: Double; var fiber: Double; var sodium: Double
            var cookingMethod: String; var confidence: Double
        }
    }

    struct PresetDTO: Codable {
        var name: String; var serving: String; var calories: Double; var protein: Double
        var carbs: Double; var fat: Double; var fiber: Double; var sodium: Double
        var category: String; var notes: String; var cookingMethod: String
    }

    struct WeightDTO: Codable { var date: Date; var weightKg: Double; var source: String }
    struct BodyFatDTO: Codable { var date: Date; var bodyFatPercentage: Double; var source: String }
    struct StepDTO: Codable { var date: Date; var steps: Int; var source: String }

    struct MeasurementDTO: Codable {
        var date: Date; var waist: Double?; var chest: Double?; var arms: Double?
        var thighs: Double?; var shoulders: Double?; var neck: Double?; var hips: Double?
        var custom: [String: Double]; var notes: String
    }

    struct GoalDTO: Codable {
        var phase: String; var startDate: Date; var startWeightKg: Double; var targetWeightKg: Double
        var targetBodyFatPercentage: Double?; var targetDate: Date?; var weeklyWeightChangeTarget: Double
        var calorieTarget: Double; var proteinTarget: Double; var stepTarget: Int
        var measurementGoals: [String: Double]; var active: Bool
    }

    struct WorkoutDTO: Codable {
        var date: Date; var title: String; var type: String; var duration: Double
        var notes: String; var perceivedDifficulty: Int; var completed: Bool; var isTemplate: Bool
        var exercises: [ExerciseDTO]

        struct ExerciseDTO: Codable {
            var name: String; var pattern: String; var equipment: String; var muscles: [String]
            var order: Int; var restSeconds: Int; var targetRPE: Double; var notes: String
            var sets: [SetDTO]
        }
        struct SetDTO: Codable {
            var order: Int; var reps: Int; var weight: Double; var duration: Double
            var distance: Double; var rpe: Double; var completed: Bool
        }
    }

    // MARK: - Export

    static func makeSnapshot(context: ModelContext) throws -> Snapshot {
        var snapshot = Snapshot()
        snapshot.meals = try context.fetch(FetchDescriptor<MealLog>()).map { meal in
            MealDTO(date: meal.date, mealType: meal.mealTypeRaw, calories: meal.calories,
                    protein: meal.protein, carbs: meal.carbs, fat: meal.fat, fiber: meal.fiber,
                    sodium: meal.sodium, confidence: meal.confidence, calorieLow: meal.calorieLow,
                    calorieHigh: meal.calorieHigh, hiddenOilLow: meal.hiddenOilLow,
                    hiddenOilHigh: meal.hiddenOilHigh, notes: meal.notes,
                    foodItems: meal.items.map {
                        .init(name: $0.name, grams: $0.grams, calories: $0.calories, protein: $0.protein,
                              carbs: $0.carbs, fat: $0.fat, fiber: $0.fiber, sodium: $0.sodium,
                              cookingMethod: $0.cookingMethodRaw, confidence: $0.confidence)
                    })
        }
        snapshot.presets = try context.fetch(FetchDescriptor<FoodPreset>()).map {
            PresetDTO(name: $0.name, serving: $0.serving, calories: $0.calories, protein: $0.protein,
                      carbs: $0.carbs, fat: $0.fat, fiber: $0.fiber, sodium: $0.sodium,
                      category: $0.category, notes: $0.notes, cookingMethod: $0.cookingMethodRaw)
        }
        snapshot.weights = try context.fetch(FetchDescriptor<BodyWeightEntry>()).map {
            WeightDTO(date: $0.date, weightKg: $0.weightKg, source: $0.sourceRaw)
        }
        snapshot.bodyFats = try context.fetch(FetchDescriptor<BodyFatEntry>()).map {
            BodyFatDTO(date: $0.date, bodyFatPercentage: $0.bodyFatPercentage, source: $0.sourceRaw)
        }
        snapshot.measurements = try context.fetch(FetchDescriptor<MeasurementEntry>()).map {
            MeasurementDTO(date: $0.date, waist: $0.waist, chest: $0.chest, arms: $0.arms,
                           thighs: $0.thighs, shoulders: $0.shoulders, neck: $0.neck, hips: $0.hips,
                           custom: $0.customMeasurements, notes: $0.notes)
        }
        snapshot.steps = try context.fetch(FetchDescriptor<StepEntry>()).map {
            StepDTO(date: $0.date, steps: $0.steps, source: $0.sourceRaw)
        }
        snapshot.goals = try context.fetch(FetchDescriptor<Goal>()).map {
            GoalDTO(phase: $0.phaseRaw, startDate: $0.startDate, startWeightKg: $0.startWeightKg,
                    targetWeightKg: $0.targetWeightKg, targetBodyFatPercentage: $0.targetBodyFatPercentage,
                    targetDate: $0.targetDate, weeklyWeightChangeTarget: $0.weeklyWeightChangeTarget,
                    calorieTarget: $0.calorieTarget, proteinTarget: $0.proteinTarget,
                    stepTarget: $0.stepTarget, measurementGoals: $0.measurementGoals, active: $0.active)
        }
        snapshot.workouts = try context.fetch(FetchDescriptor<Workout>()).map { workout in
            WorkoutDTO(date: workout.date, title: workout.title, type: workout.typeRaw,
                       duration: workout.duration, notes: workout.notes,
                       perceivedDifficulty: workout.perceivedDifficulty,
                       completed: workout.completed, isTemplate: workout.isTemplate,
                       exercises: workout.exerciseList.map { ex in
                           .init(name: ex.name, pattern: ex.movementPatternRaw, equipment: ex.equipmentRaw,
                                 muscles: ex.muscleGroupsRaw, order: ex.order, restSeconds: ex.restSeconds,
                                 targetRPE: ex.targetRPE, notes: ex.notes,
                                 sets: ex.setList.map {
                                     .init(order: $0.order, reps: $0.reps, weight: $0.weight,
                                           duration: $0.duration, distance: $0.distance,
                                           rpe: $0.rpe, completed: $0.completed)
                                 })
                       })
        }
        return snapshot
    }

    static func exportJSON(context: ModelContext) throws -> URL {
        let snapshot = try makeSnapshot(context: context)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        return try write(data: data, filename: "LockedInFit-export.json")
    }

    static func exportCSV(context: ModelContext) throws -> URL {
        let snapshot = try makeSnapshot(context: context)
        let iso = ISO8601DateFormatter()
        var csv = "== MEALS ==\ndate,mealType,calories,protein,carbs,fat,fiber,sodium,calorieLow,calorieHigh,hiddenOilLow,hiddenOilHigh,confidence,notes\n"
        for m in snapshot.meals.sorted(by: { $0.date < $1.date }) {
            csv += "\(iso.string(from: m.date)),\(m.mealType),\(Int(m.calories)),\(Int(m.protein)),\(Int(m.carbs)),\(Int(m.fat)),\(Int(m.fiber)),\(Int(m.sodium)),\(Int(m.calorieLow)),\(Int(m.calorieHigh)),\(Int(m.hiddenOilLow)),\(Int(m.hiddenOilHigh)),\(m.confidence),\(escape(m.notes))\n"
        }
        csv += "\n== BODYWEIGHT ==\ndate,weightKg,source\n"
        for w in snapshot.weights.sorted(by: { $0.date < $1.date }) {
            csv += "\(iso.string(from: w.date)),\(w.weightKg),\(w.source)\n"
        }
        csv += "\n== BODY FAT ==\ndate,bodyFatPercent,source\n"
        for f in snapshot.bodyFats.sorted(by: { $0.date < $1.date }) {
            csv += "\(iso.string(from: f.date)),\(f.bodyFatPercentage),\(f.source)\n"
        }
        csv += "\n== STEPS ==\ndate,steps,source\n"
        for s in snapshot.steps.sorted(by: { $0.date < $1.date }) {
            csv += "\(iso.string(from: s.date)),\(s.steps),\(s.source)\n"
        }
        csv += "\n== WORKOUT SETS ==\ndate,workout,exercise,pattern,setOrder,reps,weightKg,duration,rpe,completed\n"
        for w in snapshot.workouts.sorted(by: { $0.date < $1.date }) where !w.isTemplate {
            for ex in w.exercises {
                for set in ex.sets {
                    csv += "\(iso.string(from: w.date)),\(escape(w.title)),\(escape(ex.name)),\(ex.pattern),\(set.order + 1),\(set.reps),\(set.weight),\(set.duration),\(set.rpe),\(set.completed)\n"
                }
            }
        }
        return try write(data: Data(csv.utf8), filename: "LockedInFit-export.csv")
    }

    // MARK: - Import

    /// Imports a JSON snapshot, appending entries (no dedup — meant for restore into a fresh install).
    static func importJSON(from url: URL, context: ModelContext) throws -> Int {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: data)

        var count = 0
        for m in snapshot.meals {
            let meal = MealLog(date: m.date, mealType: MealType(rawValue: m.mealType) ?? .snack,
                               calories: m.calories, protein: m.protein, carbs: m.carbs, fat: m.fat,
                               fiber: m.fiber, sodium: m.sodium, confidence: m.confidence,
                               calorieLow: m.calorieLow, calorieHigh: m.calorieHigh,
                               hiddenOilLow: m.hiddenOilLow, hiddenOilHigh: m.hiddenOilHigh, notes: m.notes,
                               foodItems: m.foodItems.map {
                                   FoodItem(name: $0.name, grams: $0.grams, calories: $0.calories,
                                            protein: $0.protein, carbs: $0.carbs, fat: $0.fat, fiber: $0.fiber,
                                            sodium: $0.sodium,
                                            cookingMethod: CookingMethod(rawValue: $0.cookingMethod) ?? .unknown,
                                            confidence: $0.confidence)
                               })
            context.insert(meal); count += 1
        }
        for p in snapshot.presets {
            context.insert(FoodPreset(name: p.name, serving: p.serving, calories: p.calories,
                                      protein: p.protein, carbs: p.carbs, fat: p.fat, fiber: p.fiber,
                                      sodium: p.sodium, category: p.category, notes: p.notes,
                                      cookingMethod: CookingMethod(rawValue: p.cookingMethod) ?? .unknown))
            count += 1
        }
        for w in snapshot.weights {
            context.insert(BodyWeightEntry(date: w.date, weightKg: w.weightKg,
                                           source: EntrySource(rawValue: w.source) ?? .imported))
            count += 1
        }
        for f in snapshot.bodyFats {
            context.insert(BodyFatEntry(date: f.date, bodyFatPercentage: f.bodyFatPercentage,
                                        source: EntrySource(rawValue: f.source) ?? .imported))
            count += 1
        }
        for m in snapshot.measurements {
            context.insert(MeasurementEntry(date: m.date, waist: m.waist, chest: m.chest, arms: m.arms,
                                            thighs: m.thighs, shoulders: m.shoulders, neck: m.neck,
                                            hips: m.hips, customMeasurements: m.custom, notes: m.notes))
            count += 1
        }
        for s in snapshot.steps {
            context.insert(StepEntry(date: s.date, steps: s.steps,
                                     source: EntrySource(rawValue: s.source) ?? .imported))
            count += 1
        }
        for g in snapshot.goals {
            context.insert(Goal(phase: GoalPhase(rawValue: g.phase) ?? .custom, startDate: g.startDate,
                                startWeightKg: g.startWeightKg, targetWeightKg: g.targetWeightKg,
                                targetBodyFatPercentage: g.targetBodyFatPercentage, targetDate: g.targetDate,
                                weeklyWeightChangeTarget: g.weeklyWeightChangeTarget,
                                calorieTarget: g.calorieTarget, proteinTarget: g.proteinTarget,
                                stepTarget: g.stepTarget, measurementGoals: g.measurementGoals, active: g.active))
            count += 1
        }
        for w in snapshot.workouts {
            let workout = Workout(date: w.date, title: w.title, type: WorkoutType(rawValue: w.type) ?? .custom,
                                  duration: w.duration, notes: w.notes,
                                  perceivedDifficulty: w.perceivedDifficulty,
                                  completed: w.completed, isTemplate: w.isTemplate)
            for ex in w.exercises {
                let exercise = Exercise(name: ex.name,
                                        muscleGroups: ex.muscles.compactMap { MuscleGroup(rawValue: $0) },
                                        movementPattern: MovementPattern(rawValue: ex.pattern) ?? .horizontalPush,
                                        equipment: Equipment(rawValue: ex.equipment) ?? .barbell,
                                        order: ex.order, restSeconds: ex.restSeconds,
                                        targetRPE: ex.targetRPE, notes: ex.notes)
                for set in ex.sets {
                    exercise.sets?.append(WorkoutSet(order: set.order, reps: set.reps, weight: set.weight,
                                                     duration: set.duration, distance: set.distance,
                                                     rpe: set.rpe, completed: set.completed))
                }
                workout.exercises?.append(exercise)
            }
            context.insert(workout); count += 1
        }
        return count
    }

    // MARK: - Helpers

    private static func write(data: Data, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}
