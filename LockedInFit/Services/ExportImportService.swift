import Foundation
import SwiftData

/// Local JSON/CSV export and JSON import. No cloud anything.
enum ExportImportService {

    // MARK: - Codable snapshot

    /// Every field decodes defensively (missing keys default to empty/now)
    /// so a snapshot exported by an older build of the app, before a field
    /// existed, still imports cleanly instead of failing the whole file.
    /// This is the additive-safe-migration policy applied to the file format
    /// itself: new fields are always optional on read.
    struct Snapshot: Codable {
        var exportedAt: Date = .now
        var meals: [MealDTO] = []
        var presets: [PresetDTO] = []
        var weights: [WeightDTO] = []
        var bodyFats: [BodyFatDTO] = []
        var measurements: [MeasurementDTO] = []
        var steps: [StepDTO] = []
        var activeEnergy: [ActiveEnergyDTO] = []
        var goals: [GoalDTO] = []
        var workouts: [WorkoutDTO] = []
        var exercisePresets: [ExercisePresetDTO] = []
        var progressPhotos: [ProgressPhotoDTO] = []
        var checklistItems: [ChecklistItemDTO] = []
        var sleepLogs: [SleepLogDTO] = []
        var napLogs: [NapLogDTO] = []
        var strengthScores: [StrengthScoreDTO] = []
        var appearanceCheckIns: [AppearanceCheckInDTO] = []
        var appearanceSuggestions: [AppearanceSuggestionDTO] = []
        var workoutSchedules: [WorkoutScheduleDTO] = []
        var healthScans: [HealthScanDTO] = []
        var userSettings: [UserSettingsDTO] = []

        init() {}

        private enum CodingKeys: String, CodingKey {
            case exportedAt, meals, presets, weights, bodyFats, measurements, steps, activeEnergy,
                 goals, workouts, exercisePresets, progressPhotos, checklistItems, sleepLogs, napLogs, strengthScores,
                 appearanceCheckIns, appearanceSuggestions, workoutSchedules, healthScans, userSettings
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            exportedAt = (try? c.decode(Date.self, forKey: .exportedAt)) ?? .now
            meals = (try? c.decode([MealDTO].self, forKey: .meals)) ?? []
            presets = (try? c.decode([PresetDTO].self, forKey: .presets)) ?? []
            weights = (try? c.decode([WeightDTO].self, forKey: .weights)) ?? []
            bodyFats = (try? c.decode([BodyFatDTO].self, forKey: .bodyFats)) ?? []
            measurements = (try? c.decode([MeasurementDTO].self, forKey: .measurements)) ?? []
            steps = (try? c.decode([StepDTO].self, forKey: .steps)) ?? []
            activeEnergy = (try? c.decode([ActiveEnergyDTO].self, forKey: .activeEnergy)) ?? []
            goals = (try? c.decode([GoalDTO].self, forKey: .goals)) ?? []
            workouts = (try? c.decode([WorkoutDTO].self, forKey: .workouts)) ?? []
            exercisePresets = (try? c.decode([ExercisePresetDTO].self, forKey: .exercisePresets)) ?? []
            progressPhotos = (try? c.decode([ProgressPhotoDTO].self, forKey: .progressPhotos)) ?? []
            checklistItems = (try? c.decode([ChecklistItemDTO].self, forKey: .checklistItems)) ?? []
            sleepLogs = (try? c.decode([SleepLogDTO].self, forKey: .sleepLogs)) ?? []
            napLogs = (try? c.decode([NapLogDTO].self, forKey: .napLogs)) ?? []
            strengthScores = (try? c.decode([StrengthScoreDTO].self, forKey: .strengthScores)) ?? []
            appearanceCheckIns = (try? c.decode([AppearanceCheckInDTO].self, forKey: .appearanceCheckIns)) ?? []
            appearanceSuggestions = (try? c.decode([AppearanceSuggestionDTO].self, forKey: .appearanceSuggestions)) ?? []
            workoutSchedules = (try? c.decode([WorkoutScheduleDTO].self, forKey: .workoutSchedules)) ?? []
            healthScans = (try? c.decode([HealthScanDTO].self, forKey: .healthScans)) ?? []
            userSettings = (try? c.decode([UserSettingsDTO].self, forKey: .userSettings)) ?? []
        }

        /// Total record count across every category, used to detect sudden
        /// data loss and to decide whether a snapshot is "empty" before it's
        /// allowed to overwrite or rotate out a non-empty backup.
        var totalRecordCount: Int {
            meals.count + presets.count + weights.count + bodyFats.count + measurements.count
                + steps.count + activeEnergy.count + goals.count + workouts.count + exercisePresets.count
                + progressPhotos.count
                + checklistItems.count + sleepLogs.count + napLogs.count + strengthScores.count
                + appearanceCheckIns.count + appearanceSuggestions.count + workoutSchedules.count
                + healthScans.count
        }
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
            var fromPreset: Bool?
        }
    }

    struct PresetDTO: Codable {
        var name: String; var serving: String; var referenceGrams: Double = 0; var calories: Double
        var protein: Double
        var carbs: Double; var fat: Double; var fiber: Double; var sodium: Double
        var category: String; var notes: String; var cookingMethod: String

        init(name: String, serving: String, referenceGrams: Double, calories: Double, protein: Double,
             carbs: Double, fat: Double, fiber: Double, sodium: Double, category: String, notes: String,
             cookingMethod: String) {
            self.name = name; self.serving = serving; self.referenceGrams = referenceGrams
            self.calories = calories; self.protein = protein; self.carbs = carbs; self.fat = fat
            self.fiber = fiber; self.sodium = sodium; self.category = category; self.notes = notes
            self.cookingMethod = cookingMethod
        }

        // `referenceGrams` postdates this DTO: a backup exported before it
        // existed has no such key, and the default synthesized decoder would
        // fail the whole entry (and, since callers wrap this in `try?`,
        // silently drop every preset in the file) rather than just leaving
        // this one field at its default.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            serving = try c.decode(String.self, forKey: .serving)
            referenceGrams = try c.decodeIfPresent(Double.self, forKey: .referenceGrams) ?? 0
            calories = try c.decode(Double.self, forKey: .calories)
            protein = try c.decode(Double.self, forKey: .protein)
            carbs = try c.decode(Double.self, forKey: .carbs)
            fat = try c.decode(Double.self, forKey: .fat)
            fiber = try c.decode(Double.self, forKey: .fiber)
            sodium = try c.decode(Double.self, forKey: .sodium)
            category = try c.decode(String.self, forKey: .category)
            notes = try c.decode(String.self, forKey: .notes)
            cookingMethod = try c.decode(String.self, forKey: .cookingMethod)
        }
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

    struct ExercisePresetDTO: Codable {
        var name: String; var pattern: String; var equipment: String; var muscles: [String]
        var restSeconds: Int; var targetRPE: Double; var notes: String
        var setCount: Int; var reps: Int; var weightKg: Double
        var durationSeconds: Double; var distanceMeters: Double
    }

    struct ActiveEnergyDTO: Codable { var date: Date; var calories: Double; var source: String }

    struct ProgressPhotoDTO: Codable {
        var date: Date; var frontPhotoPath: String?; var sidePhotoPath: String?
        var backPhotoPath: String?; var notes: String
    }

    struct ChecklistItemDTO: Codable {
        var uuid: String; var title: String; var details: String; var category: String
        var createdAt: Date; var dueDate: Date; var completedAt: Date?; var isCompleted: Bool
        var recurrence: String; var customWeekdays: [Int]; var source: String; var sourceId: String?
    }

    struct SleepLogDTO: Codable {
        var uuid: String; var date: Date; var sleepStart: Date; var sleepEnd: Date; var wakeUps: Int
        var durationHours: Double; var totalScore: Double; var durationScore: Double
        var consistencyScore: Double; var interruptionScore: Double; var timingScore: Double
        var explanations: [String]; var suggestions: [String]; var napContributionScore: Double
        var napExplanations: [String]; var notes: String; var source: String
    }

    struct NapLogDTO: Codable {
        var uuid: String; var date: Date; var napStart: Date; var napEnd: Date
        var durationMinutes: Double; var notes: String; var source: String
    }

    struct StrengthScoreDTO: Codable {
        var movement: String; var score: Double; var levelName: String; var trend: Double
        var bestSetSummary: String; var estimated1RM: Double; var volumeTrend: Double
        var consistencyStreak: Int; var lastUpdated: Date
    }

    struct AppearanceCheckInDTO: Codable {
        var uuid: String; var date: Date; var kind: String; var photoPath: String?
        var frontPhotoPath: String?; var sidePhotoPath: String?; var backPhotoPath: String?
        var totalScore: Double; var qualityScore: Double; var compositionScore: Double
        var skinScore: Double; var symmetryScore: Double; var groomingScore: Double
        var puffinessScore: Double; var muscularityScore: Double; var postureScore: Double
        var trendScore: Double; var confidence: Double; var notes: String
        var faceWidthHeightRatio: Double; var createdAt: Date
    }

    struct AppearanceSuggestionDTO: Codable {
        var uuid: String; var createdAt: Date; var sourceKind: String; var title: String
        var explanation: String; var expectedImpact: String; var category: String; var priority: Int
        var status: String; var destination: String; var durationType: String
        var recurrenceRule: String?; var suggestedDate: Date?; var calendarEventId: String?
        var checklistItemId: String?; var relatedCheckInId: String?
    }

    struct WorkoutScheduleDTO: Codable {
        var uuid: String; var createdAt: Date; var title: String; var goal: String
        var experience: String; var daysPerWeek: Int; var sessionLengthMinutes: Int
        var equipment: [String]; var preferredWeekdays: [Int]; var startDate: Date; var endDate: Date?
        var syncToCalendar: Bool; var calendarEventIds: [String]; var limitations: String
        var progressionNote: String; var sessions: [SessionDTO]

        struct SessionDTO: Codable {
            var uuid: String; var weekday: Int; var date: Date?; var title: String
            var workoutType: String; var estimatedDurationMinutes: Int; var exercisePlanJSON: String
            var calendarEventId: String?; var reminderEnabled: Bool; var generatedWorkoutId: String?
        }
    }

    struct HealthScanDTO: Codable {
        var date: Date; var productName: String; var photoPath: String?; var servingSize: String
        var healthScore: Double; var satietyScore: Double; var processedLevel: String
        var calories: Double; var protein: Double; var carbs: Double; var fat: Double
        var fiber: Double; var sugar: Double; var sodium: Double; var confidence: Double
        var concerningIngredients: [String]; var notes: String
    }

    /// Every field mirrors a UserSettings raw-storage property directly (not
    /// the friendly computed enum wrapper), so this stays correct even if a
    /// future enum gains cases this build doesn't know about yet.
    struct UserSettingsDTO: Codable {
        var heightCm: Double; var age: Int; var sexRaw: String; var unitsRaw: String
        var activityAssumptionRaw: String; var applyTEF: Bool; var manualMaintenanceOverride: Double
        var adaptiveMaintenance: Double; var adaptiveMaintenanceUpdated: Date?
        var exerciseCalorieAdjustmentRaw: String
        var portionEstimationAdjustmentRaw: String?
        var sodiumLimitMg: Double; var aiModelName: String
        var aiModeRaw: String; var hasStoredAPIKey: Bool; var seededSampleData: Bool
        var clearedEmptyWorkoutsV1: Bool; var faceReminderEnabled: Bool; var faceReminderHour: Int
        var faceReminderMinute: Int; var bodyReminderEnabled: Bool; var bodyReminderFrequencyRaw: String
        var workoutRemindersEnabled: Bool; var defaultWorkoutReminderMinutes: Int
        var mealReminderEnabled: Bool; var sleepReminderEnabled: Bool; var sleepReminderHour: Int
        var sleepReminderMinute: Int; var checklistReminderEnabled: Bool
        var dietaryLimitAlertsEnabled: Bool; var goalAlertsEnabled: Bool
        var crossAppSharingEnabled: Bool
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
                              cookingMethod: $0.cookingMethodRaw, confidence: $0.confidence,
                              fromPreset: $0.fromPreset)
                    })
        }
        snapshot.presets = try context.fetch(FetchDescriptor<FoodPreset>()).map {
            PresetDTO(name: $0.name, serving: $0.serving, referenceGrams: $0.referenceGrams,
                      calories: $0.calories, protein: $0.protein,
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
        snapshot.activeEnergy = try context.fetch(FetchDescriptor<ActiveEnergyEntry>()).map {
            ActiveEnergyDTO(date: $0.date, calories: $0.calories, source: $0.sourceRaw)
        }
        snapshot.progressPhotos = try context.fetch(FetchDescriptor<ProgressPhoto>()).map {
            ProgressPhotoDTO(date: $0.date, frontPhotoPath: $0.frontPhotoPath, sidePhotoPath: $0.sidePhotoPath,
                             backPhotoPath: $0.backPhotoPath, notes: $0.notes)
        }
        snapshot.checklistItems = try context.fetch(FetchDescriptor<DailyChecklistItem>()).map {
            ChecklistItemDTO(uuid: $0.uuid, title: $0.title, details: $0.details, category: $0.categoryRaw,
                             createdAt: $0.createdAt, dueDate: $0.dueDate, completedAt: $0.completedAt,
                             isCompleted: $0.isCompleted, recurrence: $0.recurrenceRaw,
                             customWeekdays: $0.customWeekdays, source: $0.sourceRaw, sourceId: $0.sourceId)
        }
        snapshot.sleepLogs = try context.fetch(FetchDescriptor<SleepLog>()).map {
            SleepLogDTO(uuid: $0.uuid, date: $0.date, sleepStart: $0.sleepStart, sleepEnd: $0.sleepEnd,
                        wakeUps: $0.wakeUps, durationHours: $0.durationHours, totalScore: $0.totalScore,
                        durationScore: $0.durationScore, consistencyScore: $0.consistencyScore,
                        interruptionScore: $0.interruptionScore, timingScore: $0.timingScore,
                        explanations: $0.explanations, suggestions: $0.suggestions,
                        napContributionScore: $0.napContributionScore, napExplanations: $0.napExplanations,
                        notes: $0.notes, source: $0.sourceRaw)
        }
        snapshot.napLogs = try context.fetch(FetchDescriptor<NapLog>()).map {
            NapLogDTO(uuid: $0.uuid, date: $0.date, napStart: $0.napStart, napEnd: $0.napEnd,
                     durationMinutes: $0.durationMinutes, notes: $0.notes, source: $0.sourceRaw)
        }
        snapshot.strengthScores = try context.fetch(FetchDescriptor<StrengthScore>()).map {
            StrengthScoreDTO(movement: $0.movementRaw, score: $0.score, levelName: $0.levelName,
                             trend: $0.trend, bestSetSummary: $0.bestSetSummary,
                             estimated1RM: $0.estimated1RM, volumeTrend: $0.volumeTrend,
                             consistencyStreak: $0.consistencyStreak, lastUpdated: $0.lastUpdated)
        }
        snapshot.appearanceCheckIns = try context.fetch(FetchDescriptor<AppearanceCheckIn>()).map {
            AppearanceCheckInDTO(uuid: $0.uuid, date: $0.date, kind: $0.kindRaw, photoPath: $0.photoPath,
                                 frontPhotoPath: $0.frontPhotoPath, sidePhotoPath: $0.sidePhotoPath,
                                 backPhotoPath: $0.backPhotoPath, totalScore: $0.totalScore,
                                 qualityScore: $0.qualityScore, compositionScore: $0.compositionScore,
                                 skinScore: $0.skinScore, symmetryScore: $0.symmetryScore,
                                 groomingScore: $0.groomingScore, puffinessScore: $0.puffinessScore,
                                 muscularityScore: $0.muscularityScore, postureScore: $0.postureScore,
                                 trendScore: $0.trendScore, confidence: $0.confidence, notes: $0.notes,
                                 faceWidthHeightRatio: $0.faceWidthHeightRatio, createdAt: $0.createdAt)
        }
        snapshot.appearanceSuggestions = try context.fetch(FetchDescriptor<AppearanceSuggestion>()).map {
            AppearanceSuggestionDTO(uuid: $0.uuid, createdAt: $0.createdAt, sourceKind: $0.sourceKindRaw,
                                    title: $0.title, explanation: $0.explanation,
                                    expectedImpact: $0.expectedImpact, category: $0.categoryRaw,
                                    priority: $0.priority, status: $0.statusRaw,
                                    destination: $0.destinationRaw, durationType: $0.durationTypeRaw,
                                    recurrenceRule: $0.recurrenceRule, suggestedDate: $0.suggestedDate,
                                    calendarEventId: $0.calendarEventId, checklistItemId: $0.checklistItemId,
                                    relatedCheckInId: $0.relatedCheckInId)
        }
        snapshot.workoutSchedules = try context.fetch(FetchDescriptor<WorkoutSchedule>()).map { schedule in
            WorkoutScheduleDTO(uuid: schedule.uuid, createdAt: schedule.createdAt, title: schedule.title,
                              goal: schedule.goalRaw, experience: schedule.experienceRaw,
                              daysPerWeek: schedule.daysPerWeek, sessionLengthMinutes: schedule.sessionLengthMinutes,
                              equipment: schedule.equipmentRaw, preferredWeekdays: schedule.preferredWeekdays,
                              startDate: schedule.startDate, endDate: schedule.endDate,
                              syncToCalendar: schedule.syncToCalendar, calendarEventIds: schedule.calendarEventIds,
                              limitations: schedule.limitations, progressionNote: schedule.progressionNote,
                              sessions: schedule.sessionList.map {
                                  .init(uuid: $0.uuid, weekday: $0.weekday, date: $0.date, title: $0.title,
                                        workoutType: $0.workoutTypeRaw,
                                        estimatedDurationMinutes: $0.estimatedDurationMinutes,
                                        exercisePlanJSON: $0.exercisePlanJSON, calendarEventId: $0.calendarEventId,
                                        reminderEnabled: $0.reminderEnabled, generatedWorkoutId: $0.generatedWorkoutId)
                              })
        }
        snapshot.healthScans = try context.fetch(FetchDescriptor<HealthScan>()).map {
            HealthScanDTO(date: $0.date, productName: $0.productName, photoPath: $0.photoPath,
                         servingSize: $0.servingSize, healthScore: $0.healthScore,
                         satietyScore: $0.satietyScore, processedLevel: $0.processedLevelRaw,
                         calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat,
                         fiber: $0.fiber, sugar: $0.sugar, sodium: $0.sodium, confidence: $0.confidence,
                         concerningIngredients: $0.concerningIngredientsRaw, notes: $0.notes)
        }
        snapshot.userSettings = try context.fetch(FetchDescriptor<UserSettings>()).map {
            UserSettingsDTO(heightCm: $0.heightCm, age: $0.age, sexRaw: $0.sexRaw, unitsRaw: $0.unitsRaw,
                            activityAssumptionRaw: $0.activityAssumptionRaw, applyTEF: $0.applyTEF,
                            manualMaintenanceOverride: $0.manualMaintenanceOverride,
                            adaptiveMaintenance: $0.adaptiveMaintenance,
                            adaptiveMaintenanceUpdated: $0.adaptiveMaintenanceUpdated,
                            exerciseCalorieAdjustmentRaw: $0.exerciseCalorieAdjustmentRaw,
                            portionEstimationAdjustmentRaw: $0.portionEstimationAdjustmentRaw,
                            sodiumLimitMg: $0.sodiumLimitMg, aiModelName: $0.aiModelName,
                            aiModeRaw: $0.aiModeRaw, hasStoredAPIKey: $0.hasStoredAPIKey,
                            seededSampleData: $0.seededSampleData,
                            clearedEmptyWorkoutsV1: $0.clearedEmptyWorkoutsV1,
                            faceReminderEnabled: $0.faceReminderEnabled, faceReminderHour: $0.faceReminderHour,
                            faceReminderMinute: $0.faceReminderMinute, bodyReminderEnabled: $0.bodyReminderEnabled,
                            bodyReminderFrequencyRaw: $0.bodyReminderFrequencyRaw,
                            workoutRemindersEnabled: $0.workoutRemindersEnabled,
                            defaultWorkoutReminderMinutes: $0.defaultWorkoutReminderMinutes,
                            mealReminderEnabled: $0.mealReminderEnabled,
                            sleepReminderEnabled: $0.sleepReminderEnabled,
                            sleepReminderHour: $0.sleepReminderHour, sleepReminderMinute: $0.sleepReminderMinute,
                            checklistReminderEnabled: $0.checklistReminderEnabled,
                            dietaryLimitAlertsEnabled: $0.dietaryLimitAlertsEnabled,
                            goalAlertsEnabled: $0.goalAlertsEnabled,
                            crossAppSharingEnabled: $0.crossAppSharingEnabled)
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
        snapshot.exercisePresets = try context.fetch(FetchDescriptor<ExercisePreset>()).map {
            ExercisePresetDTO(name: $0.name, pattern: $0.movementPatternRaw, equipment: $0.equipmentRaw,
                              muscles: $0.muscleGroupsRaw, restSeconds: $0.restSeconds, targetRPE: $0.targetRPE,
                              notes: $0.notes, setCount: $0.setCount, reps: $0.reps, weightKg: $0.weightKg,
                              durationSeconds: $0.durationSeconds, distanceMeters: $0.distanceMeters)
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

    /// A dedup identity for content that has no natural uuid (predates one
    /// existing, or never needed one for in-app purposes), built from fields
    /// that are extremely unlikely to coincidentally match for two
    /// genuinely different real-world entries, but WILL match exactly for
    /// the same entry re-imported from an overlapping/duplicate backup.
    /// Second precision: `.iso8601` export/import round-trips dates to
    /// whole seconds, so comparing a decoded DTO's date against a live
    /// record's full sub-second-precision Date at exact equality would
    /// never match even for the identical original event.
    private static func sec(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970.rounded()) }

    /// Imports a JSON snapshot, appending only entries NOT already present.
    /// Restoring the same (or an overlapping) backup more than once, or
    /// restoring onto data that was never actually lost, used to duplicate
    /// every record unconditionally — exactly the "restore just duplicates
    /// what's already there instead of bringing back what's missing" bug.
    /// Each type is deduped either by its own persisted uuid (checklist
    /// items, sleep/nap logs, appearance check-ins/suggestions, workout
    /// schedules) or, for types that predate having one, by the content
    /// signature above.
    static func importJSON(from url: URL, context: ModelContext) throws -> Int {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: data)

        var count = 0
        var existingMealSignatures = Set((try? context.fetch(FetchDescriptor<MealLog>()))?.map {
            "\(sec($0.date))|\($0.mealTypeRaw)|\($0.calories)|\($0.protein)|\($0.carbs)|\($0.fat)|\($0.notes)"
        } ?? [])
        for m in snapshot.meals {
            let signature = "\(sec(m.date))|\(m.mealType)|\(m.calories)|\(m.protein)|\(m.carbs)|\(m.fat)|\(m.notes)"
            guard !existingMealSignatures.contains(signature) else { continue }
            existingMealSignatures.insert(signature)
            let meal = MealLog(date: m.date, mealType: MealType(rawValue: m.mealType) ?? .snack,
                               calories: m.calories, protein: m.protein, carbs: m.carbs, fat: m.fat,
                               fiber: m.fiber, sodium: m.sodium, confidence: m.confidence,
                               calorieLow: m.calorieLow, calorieHigh: m.calorieHigh,
                               hiddenOilLow: m.hiddenOilLow, hiddenOilHigh: m.hiddenOilHigh, notes: m.notes,
                               foodItems: m.foodItems.enumerated().map { index, item in
                                   FoodItem(name: item.name, grams: item.grams, calories: item.calories,
                                            protein: item.protein, carbs: item.carbs, fat: item.fat, fiber: item.fiber,
                                            sodium: item.sodium,
                                            cookingMethod: CookingMethod(rawValue: item.cookingMethod) ?? .unknown,
                                            confidence: item.confidence, order: index,
                                            fromPreset: item.fromPreset ?? false)
                               })
            context.insert(meal); count += 1
        }
        var existingPresetSignatures = Set((try? context.fetch(FetchDescriptor<FoodPreset>()))?.map {
            "\($0.name)|\($0.serving)|\($0.calories)"
        } ?? [])
        for p in snapshot.presets {
            let signature = "\(p.name)|\(p.serving)|\(p.calories)"
            guard !existingPresetSignatures.contains(signature) else { continue }
            existingPresetSignatures.insert(signature)
            context.insert(FoodPreset(name: p.name, serving: p.serving, referenceGrams: p.referenceGrams,
                                      calories: p.calories, protein: p.protein, carbs: p.carbs, fat: p.fat,
                                      fiber: p.fiber, sodium: p.sodium, category: p.category, notes: p.notes,
                                      cookingMethod: CookingMethod(rawValue: p.cookingMethod) ?? .unknown))
            count += 1
        }
        var existingWeightSignatures = Set((try? context.fetch(FetchDescriptor<BodyWeightEntry>()))?.map {
            "\(sec($0.date))|\($0.weightKg)|\($0.sourceRaw)"
        } ?? [])
        for w in snapshot.weights {
            let signature = "\(sec(w.date))|\(w.weightKg)|\(w.source)"
            guard !existingWeightSignatures.contains(signature) else { continue }
            existingWeightSignatures.insert(signature)
            context.insert(BodyWeightEntry(date: w.date, weightKg: w.weightKg,
                                           source: EntrySource(rawValue: w.source) ?? .imported))
            count += 1
        }
        var existingBodyFatSignatures = Set((try? context.fetch(FetchDescriptor<BodyFatEntry>()))?.map {
            "\(sec($0.date))|\($0.bodyFatPercentage)|\($0.sourceRaw)"
        } ?? [])
        for f in snapshot.bodyFats {
            let signature = "\(sec(f.date))|\(f.bodyFatPercentage)|\(f.source)"
            guard !existingBodyFatSignatures.contains(signature) else { continue }
            existingBodyFatSignatures.insert(signature)
            context.insert(BodyFatEntry(date: f.date, bodyFatPercentage: f.bodyFatPercentage,
                                        source: EntrySource(rawValue: f.source) ?? .imported))
            count += 1
        }
        var existingMeasurementDates = Set((try? context.fetch(FetchDescriptor<MeasurementEntry>()))?.map { sec($0.date) } ?? [])
        for m in snapshot.measurements {
            let signature = sec(m.date)
            guard !existingMeasurementDates.contains(signature) else { continue }
            existingMeasurementDates.insert(signature)
            context.insert(MeasurementEntry(date: m.date, waist: m.waist, chest: m.chest, arms: m.arms,
                                            thighs: m.thighs, shoulders: m.shoulders, neck: m.neck,
                                            hips: m.hips, customMeasurements: m.custom, notes: m.notes))
            count += 1
        }
        var existingStepSignatures = Set((try? context.fetch(FetchDescriptor<StepEntry>()))?.map {
            "\(sec($0.date))|\($0.sourceRaw)"
        } ?? [])
        for s in snapshot.steps {
            let signature = "\(sec(s.date))|\(s.source)"
            guard !existingStepSignatures.contains(signature) else { continue }
            existingStepSignatures.insert(signature)
            context.insert(StepEntry(date: s.date, steps: s.steps,
                                     source: EntrySource(rawValue: s.source) ?? .imported))
            count += 1
        }
        var existingGoalSignatures = Set((try? context.fetch(FetchDescriptor<Goal>()))?.map {
            "\(sec($0.startDate))|\($0.phaseRaw)|\($0.targetWeightKg)"
        } ?? [])
        for g in snapshot.goals {
            let signature = "\(sec(g.startDate))|\(g.phase)|\(g.targetWeightKg)"
            guard !existingGoalSignatures.contains(signature) else { continue }
            existingGoalSignatures.insert(signature)
            context.insert(Goal(phase: GoalPhase(rawValue: g.phase) ?? .custom, startDate: g.startDate,
                                startWeightKg: g.startWeightKg, targetWeightKg: g.targetWeightKg,
                                targetBodyFatPercentage: g.targetBodyFatPercentage, targetDate: g.targetDate,
                                weeklyWeightChangeTarget: g.weeklyWeightChangeTarget,
                                calorieTarget: g.calorieTarget, proteinTarget: g.proteinTarget,
                                stepTarget: g.stepTarget, measurementGoals: g.measurementGoals, active: g.active))
            count += 1
        }
        var existingWorkoutSignatures = Set((try? context.fetch(FetchDescriptor<Workout>()))?.map {
            "\(sec($0.date))|\($0.title)|\($0.typeRaw)"
        } ?? [])
        for w in snapshot.workouts {
            let signature = "\(sec(w.date))|\(w.title)|\(w.type)"
            guard !existingWorkoutSignatures.contains(signature) else { continue }
            existingWorkoutSignatures.insert(signature)
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
        var existingExercisePresetNames = Set((try? context.fetch(FetchDescriptor<ExercisePreset>()))?.map {
            $0.name.lowercased()
        } ?? [])
        for p in snapshot.exercisePresets {
            let key = p.name.lowercased()
            guard !key.isEmpty, !existingExercisePresetNames.contains(key) else { continue }
            existingExercisePresetNames.insert(key)
            context.insert(ExercisePreset(
                name: p.name,
                muscleGroups: p.muscles.compactMap { MuscleGroup(rawValue: $0) },
                movementPattern: MovementPattern(rawValue: p.pattern) ?? .horizontalPush,
                equipment: Equipment(rawValue: p.equipment) ?? .barbell,
                restSeconds: p.restSeconds, targetRPE: p.targetRPE, notes: p.notes,
                setCount: p.setCount, reps: p.reps, weightKg: p.weightKg,
                durationSeconds: p.durationSeconds, distanceMeters: p.distanceMeters))
            count += 1
        }
        var existingActiveEnergySignatures = Set((try? context.fetch(FetchDescriptor<ActiveEnergyEntry>()))?.map {
            "\(sec($0.date))|\($0.sourceRaw)"
        } ?? [])
        for a in snapshot.activeEnergy {
            let signature = "\(sec(a.date))|\(a.source)"
            guard !existingActiveEnergySignatures.contains(signature) else { continue }
            existingActiveEnergySignatures.insert(signature)
            context.insert(ActiveEnergyEntry(date: a.date, calories: a.calories,
                                             source: EntrySource(rawValue: a.source) ?? .imported))
            count += 1
        }
        var existingProgressPhotoDates = Set((try? context.fetch(FetchDescriptor<ProgressPhoto>()))?.map { sec($0.date) } ?? [])
        for p in snapshot.progressPhotos {
            let signature = sec(p.date)
            guard !existingProgressPhotoDates.contains(signature) else { continue }
            existingProgressPhotoDates.insert(signature)
            context.insert(ProgressPhoto(date: p.date, frontPhotoPath: p.frontPhotoPath,
                                         sidePhotoPath: p.sidePhotoPath, backPhotoPath: p.backPhotoPath,
                                         notes: p.notes))
            count += 1
        }
        var existingChecklistUUIDs = Set((try? context.fetch(FetchDescriptor<DailyChecklistItem>()))?.map { $0.uuid } ?? [])
        for i in snapshot.checklistItems {
            guard !existingChecklistUUIDs.contains(i.uuid) else { continue }
            existingChecklistUUIDs.insert(i.uuid)
            let item = DailyChecklistItem(title: i.title, details: i.details,
                                          category: ChecklistCategory(rawValue: i.category) ?? .manual,
                                          dueDate: i.dueDate,
                                          recurrence: ChecklistRecurrence(rawValue: i.recurrence) ?? .none,
                                          customWeekdays: i.customWeekdays,
                                          source: ChecklistSource(rawValue: i.source) ?? .manual,
                                          sourceId: i.sourceId)
            item.uuid = i.uuid
            item.createdAt = i.createdAt
            item.completedAt = i.completedAt
            item.isCompleted = i.isCompleted
            context.insert(item); count += 1
        }
        var existingSleepUUIDs = Set((try? context.fetch(FetchDescriptor<SleepLog>()))?.map { $0.uuid } ?? [])
        for s in snapshot.sleepLogs {
            guard !existingSleepUUIDs.contains(s.uuid) else { continue }
            existingSleepUUIDs.insert(s.uuid)
            let log = SleepLog(date: s.date, sleepStart: s.sleepStart, sleepEnd: s.sleepEnd,
                               wakeUps: s.wakeUps, durationHours: s.durationHours, totalScore: s.totalScore,
                               notes: s.notes, source: EntrySource(rawValue: s.source) ?? .imported)
            log.uuid = s.uuid
            log.durationScore = s.durationScore
            log.consistencyScore = s.consistencyScore
            log.interruptionScore = s.interruptionScore
            log.timingScore = s.timingScore
            log.explanations = s.explanations
            log.suggestions = s.suggestions
            log.napContributionScore = s.napContributionScore
            log.napExplanations = s.napExplanations
            context.insert(log); count += 1
        }
        var existingNapUUIDs = Set((try? context.fetch(FetchDescriptor<NapLog>()))?.map { $0.uuid } ?? [])
        for n in snapshot.napLogs {
            guard !existingNapUUIDs.contains(n.uuid) else { continue }
            existingNapUUIDs.insert(n.uuid)
            context.insert(NapLog(date: n.date, napStart: n.napStart, napEnd: n.napEnd,
                                  durationMinutes: n.durationMinutes, notes: n.notes,
                                  source: EntrySource(rawValue: n.source) ?? .imported))
            count += 1
        }
        var existingStrengthMovements = Set((try? context.fetch(FetchDescriptor<StrengthScore>()))?.map { $0.movementRaw } ?? [])
        for s in snapshot.strengthScores {
            guard !existingStrengthMovements.contains(s.movement) else { continue }
            existingStrengthMovements.insert(s.movement)
            let score = StrengthScore(movement: MovementPattern(rawValue: s.movement) ?? .squat)
            score.score = s.score
            score.levelName = s.levelName
            score.trend = s.trend
            score.bestSetSummary = s.bestSetSummary
            score.estimated1RM = s.estimated1RM
            score.volumeTrend = s.volumeTrend
            score.consistencyStreak = s.consistencyStreak
            score.lastUpdated = s.lastUpdated
            context.insert(score); count += 1
        }
        var existingCheckInUUIDs = Set((try? context.fetch(FetchDescriptor<AppearanceCheckIn>()))?.map { $0.uuid } ?? [])
        for c in snapshot.appearanceCheckIns {
            guard !existingCheckInUUIDs.contains(c.uuid) else { continue }
            existingCheckInUUIDs.insert(c.uuid)
            let checkIn = AppearanceCheckIn(date: c.date, kind: AppearanceCheckInKind(rawValue: c.kind) ?? .face,
                                            photoPath: c.photoPath, frontPhotoPath: c.frontPhotoPath,
                                            sidePhotoPath: c.sidePhotoPath, backPhotoPath: c.backPhotoPath,
                                            totalScore: c.totalScore, confidence: c.confidence, notes: c.notes)
            checkIn.uuid = c.uuid
            checkIn.qualityScore = c.qualityScore
            checkIn.compositionScore = c.compositionScore
            checkIn.skinScore = c.skinScore
            checkIn.symmetryScore = c.symmetryScore
            checkIn.groomingScore = c.groomingScore
            checkIn.puffinessScore = c.puffinessScore
            checkIn.muscularityScore = c.muscularityScore
            checkIn.postureScore = c.postureScore
            checkIn.trendScore = c.trendScore
            checkIn.faceWidthHeightRatio = c.faceWidthHeightRatio
            checkIn.createdAt = c.createdAt
            context.insert(checkIn); count += 1
        }
        var existingSuggestionUUIDs = Set((try? context.fetch(FetchDescriptor<AppearanceSuggestion>()))?.map { $0.uuid } ?? [])
        for s in snapshot.appearanceSuggestions {
            guard !existingSuggestionUUIDs.contains(s.uuid) else { continue }
            existingSuggestionUUIDs.insert(s.uuid)
            let suggestion = AppearanceSuggestion(sourceKind: s.sourceKind, title: s.title,
                                                  explanation: s.explanation, expectedImpact: s.expectedImpact,
                                                  category: AppearanceSuggestionCategory(rawValue: s.category) ?? .skin,
                                                  priority: s.priority,
                                                  durationType: SuggestionDurationType(rawValue: s.durationType) ?? .shortTerm,
                                                  destination: AppearanceSuggestionDestination(rawValue: s.destination) ?? .saveOnly,
                                                  relatedCheckInId: s.relatedCheckInId)
            suggestion.uuid = s.uuid
            suggestion.createdAt = s.createdAt
            suggestion.statusRaw = s.status
            suggestion.recurrenceRule = s.recurrenceRule
            suggestion.suggestedDate = s.suggestedDate
            suggestion.calendarEventId = s.calendarEventId
            suggestion.checklistItemId = s.checklistItemId
            context.insert(suggestion); count += 1
        }
        var existingScheduleUUIDs = Set((try? context.fetch(FetchDescriptor<WorkoutSchedule>()))?.map { $0.uuid } ?? [])
        for sc in snapshot.workoutSchedules {
            guard !existingScheduleUUIDs.contains(sc.uuid) else { continue }
            existingScheduleUUIDs.insert(sc.uuid)
            let schedule = WorkoutSchedule(
                title: sc.title,
                goal: WorkoutScheduleGoal(rawValue: sc.goal) ?? .generalFitness,
                experience: WorkoutExperienceLevel(rawValue: sc.experience) ?? .intermediate,
                daysPerWeek: sc.daysPerWeek, sessionLengthMinutes: sc.sessionLengthMinutes,
                equipment: sc.equipment.compactMap { Equipment(rawValue: $0) },
                preferredWeekdays: sc.preferredWeekdays, startDate: sc.startDate, endDate: sc.endDate,
                syncToCalendar: sc.syncToCalendar, limitations: sc.limitations,
                progressionNote: sc.progressionNote)
            schedule.uuid = sc.uuid
            schedule.createdAt = sc.createdAt
            schedule.calendarEventIds = sc.calendarEventIds
            for sd in sc.sessions {
                let session = WorkoutScheduleSession(weekday: sd.weekday, date: sd.date, title: sd.title,
                                                     workoutType: WorkoutType(rawValue: sd.workoutType) ?? .fullBody,
                                                     estimatedDurationMinutes: sd.estimatedDurationMinutes,
                                                     plannedExercises: [], reminderEnabled: sd.reminderEnabled)
                session.uuid = sd.uuid
                session.exercisePlanJSON = sd.exercisePlanJSON
                session.calendarEventId = sd.calendarEventId
                session.generatedWorkoutId = sd.generatedWorkoutId
                schedule.sessions?.append(session)
            }
            context.insert(schedule); count += 1
        }
        var existingHealthScanSignatures = Set((try? context.fetch(FetchDescriptor<HealthScan>()))?.map {
            "\(sec($0.date))|\($0.productName)"
        } ?? [])
        for h in snapshot.healthScans {
            let signature = "\(sec(h.date))|\(h.productName)"
            guard !existingHealthScanSignatures.contains(signature) else { continue }
            existingHealthScanSignatures.insert(signature)
            context.insert(HealthScan(date: h.date, productName: h.productName, photoPath: h.photoPath,
                                      servingSize: h.servingSize, healthScore: h.healthScore,
                                      satietyScore: h.satietyScore,
                                      processedLevel: ProcessedLevel(rawValue: h.processedLevel) ?? .unknown,
                                      calories: h.calories, protein: h.protein, carbs: h.carbs, fat: h.fat,
                                      fiber: h.fiber, sugar: h.sugar, sodium: h.sodium,
                                      confidence: h.confidence, concerningIngredients: h.concerningIngredients,
                                      notes: h.notes))
            count += 1
        }
        if let u = snapshot.userSettings.first {
            let existing = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
            let settings = existing ?? UserSettings()
            if existing == nil { context.insert(settings) }
            settings.heightCm = u.heightCm
            settings.age = u.age
            settings.sexRaw = u.sexRaw
            settings.unitsRaw = u.unitsRaw
            settings.activityAssumptionRaw = u.activityAssumptionRaw
            settings.applyTEF = u.applyTEF
            settings.manualMaintenanceOverride = u.manualMaintenanceOverride
            settings.adaptiveMaintenance = u.adaptiveMaintenance
            settings.adaptiveMaintenanceUpdated = u.adaptiveMaintenanceUpdated
            settings.exerciseCalorieAdjustmentRaw = u.exerciseCalorieAdjustmentRaw
            settings.portionEstimationAdjustmentRaw = u.portionEstimationAdjustmentRaw ?? PortionEstimationAdjustment.off.rawValue
            settings.sodiumLimitMg = u.sodiumLimitMg
            settings.aiModelName = u.aiModelName
            settings.aiModeRaw = u.aiModeRaw
            settings.hasStoredAPIKey = u.hasStoredAPIKey
            settings.seededSampleData = u.seededSampleData
            settings.clearedEmptyWorkoutsV1 = u.clearedEmptyWorkoutsV1
            settings.faceReminderEnabled = u.faceReminderEnabled
            settings.faceReminderHour = u.faceReminderHour
            settings.faceReminderMinute = u.faceReminderMinute
            settings.bodyReminderEnabled = u.bodyReminderEnabled
            settings.bodyReminderFrequencyRaw = u.bodyReminderFrequencyRaw
            settings.workoutRemindersEnabled = u.workoutRemindersEnabled
            settings.defaultWorkoutReminderMinutes = u.defaultWorkoutReminderMinutes
            settings.mealReminderEnabled = u.mealReminderEnabled
            settings.sleepReminderEnabled = u.sleepReminderEnabled
            settings.sleepReminderHour = u.sleepReminderHour
            settings.sleepReminderMinute = u.sleepReminderMinute
            settings.checklistReminderEnabled = u.checklistReminderEnabled
            settings.dietaryLimitAlertsEnabled = u.dietaryLimitAlertsEnabled
            settings.goalAlertsEnabled = u.goalAlertsEnabled
            settings.crossAppSharingEnabled = u.crossAppSharingEnabled
            count += 1
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
