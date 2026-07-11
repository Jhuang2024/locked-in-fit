import Foundation

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "carrot"
        }
    }

    static func guess(for date: Date = .now) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

enum GoalPhase: String, Codable, CaseIterable, Identifiable {
    case cut, maintain
    case leanBulk = "lean_bulk"
    case aggressiveBulk = "aggressive_bulk"
    case custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .cut: return "Cut"
        case .maintain: return "Maintain"
        case .leanBulk: return "Lean Bulk"
        case .aggressiveBulk: return "Aggressive Bulk"
        case .custom: return "Custom"
        }
    }
    /// Default weekly bodyweight change in kg for the phase.
    var defaultWeeklyChangeKg: Double {
        switch self {
        case .cut: return -0.5
        case .maintain: return 0
        case .leanBulk: return 0.2
        case .aggressiveBulk: return 0.45
        case .custom: return 0
        }
    }
    var systemImage: String {
        switch self {
        case .cut: return "arrow.down.right"
        case .maintain: return "equal"
        case .leanBulk: return "arrow.up.right"
        case .aggressiveBulk: return "arrow.up.forward.app"
        case .custom: return "slider.horizontal.3"
        }
    }
}

enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    case strength, hypertrophy
    case fullBody = "full_body"
    case upperLower = "upper_lower"
    case pushPullLegs = "push_pull_legs"
    case conditioning, mobility, custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .strength: return "Strength"
        case .hypertrophy: return "Hypertrophy"
        case .fullBody: return "Full Body"
        case .upperLower: return "Upper / Lower"
        case .pushPullLegs: return "Push / Pull / Legs"
        case .conditioning: return "Conditioning"
        case .mobility: return "Mobility"
        case .custom: return "Custom"
        }
    }
}

enum MovementPattern: String, Codable, CaseIterable, Identifiable {
    case squat
    case hinge
    case horizontalPush = "horizontal_push"
    case verticalPush = "vertical_push"
    case horizontalPull = "horizontal_pull"
    case verticalPull = "vertical_pull"
    case core
    case conditioning

    var id: String { rawValue }
    var label: String {
        switch self {
        case .squat: return "Squat"
        case .hinge: return "Hinge"
        case .horizontalPush: return "Horizontal Push"
        case .verticalPush: return "Vertical Push"
        case .horizontalPull: return "Horizontal Pull"
        case .verticalPull: return "Vertical Pull"
        case .core: return "Core"
        case .conditioning: return "Conditioning"
        }
    }
    var systemImage: String {
        switch self {
        case .squat: return "figure.strengthtraining.functional"
        case .hinge: return "figure.strengthtraining.traditional"
        case .horizontalPush: return "arrow.right.circle"
        case .verticalPush: return "arrow.up.circle"
        case .horizontalPull: return "arrow.left.circle"
        case .verticalPull: return "arrow.down.circle"
        case .core: return "circle.grid.cross"
        case .conditioning: return "heart.circle"
        }
    }
}

enum CookingMethod: String, Codable, CaseIterable, Identifiable {
    case steamed, boiled, soup, grilled, baked, raw
    case stirFried = "stir-fried"
    case deepFried = "deep-fried"
    case braised
    case restaurantHighOil = "restaurant_high_oil"
    case unknown

    var id: String { rawValue }
    var label: String {
        switch self {
        case .stirFried: return "Stir-fried"
        case .deepFried: return "Deep-fried"
        case .restaurantHighOil: return "Restaurant (High Oil)"
        default: return rawValue.capitalized
        }
    }
}

enum ProcessedLevel: String, Codable, CaseIterable, Identifiable {
    case unprocessed
    case minimallyProcessed = "minimally_processed"
    case processed
    case ultraProcessed = "ultra_processed"
    case unknown

    var id: String { rawValue }
    var label: String {
        switch self {
        case .unprocessed: return "Unprocessed"
        case .minimallyProcessed: return "Minimally Processed"
        case .processed: return "Processed"
        case .ultraProcessed: return "Ultra-Processed"
        case .unknown: return "Unknown"
        }
    }
    var systemImage: String {
        switch self {
        case .unprocessed: return "leaf"
        case .minimallyProcessed: return "leaf.fill"
        case .processed: return "shippingbox"
        case .ultraProcessed: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum MealAnalysisState: String, Codable {
    case notAnalyzed = "not_analyzed"
    case analyzing
    case completed
    case failed

    var label: String {
        switch self {
        case .notAnalyzed: return "Not analyzed"
        case .analyzing: return "Analyzing…"
        case .completed: return "Analyzed"
        case .failed: return "Analysis unavailable"
        }
    }
}

enum EntrySource: String, Codable, CaseIterable {
    case manual
    case healthKit = "health_kit"
    case imported

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .healthKit: return "Apple Health"
        case .imported: return "Imported"
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var label: String { self == .metric ? "Metric (kg, cm)" : "Imperial (lb, in)" }
}

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum ActivityAssumption: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Multiplier applied to BMR before step-based activity is added.
    var nonStepMultiplier: Double {
        switch self {
        case .sedentary: return 1.10
        case .light: return 1.15
        case .moderate: return 1.20
        case .active: return 1.28
        }
    }
}

enum ExerciseCalorieAdjustment: String, Codable, CaseIterable, Identifiable {
    case off, conservative, moderate, full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .conservative: return "Conservative"
        case .moderate: return "Moderate"
        case .full: return "Full"
        }
    }

    var multiplier: Double {
        switch self {
        case .off: return 0
        case .conservative: return 0.45
        case .moderate: return 0.65
        case .full: return 1
        }
    }

    var detail: String {
        switch self {
        case .off: return "Do not add exercise calories back."
        case .conservative: return "Add back 45% of estimated activity calories."
        case .moderate: return "Add back 65% of estimated activity calories."
        case .full: return "Add back all tracked activity calories."
        }
    }
}

/// How much to inflate logged food calories to offset the well-documented
/// tendency to underestimate portion sizes. Applied to logged food calories
/// only — hidden cooking oil is estimated separately.
enum PortionEstimationAdjustment: String, Codable, CaseIterable, Identifiable {
    case off, conservative, moderate, full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .conservative: return "Conservative"
        case .moderate: return "Moderate"
        case .full: return "Full"
        }
    }

    /// Fraction added on top of logged food calories.
    var uplift: Double {
        switch self {
        case .off: return 0
        case .conservative: return 0.05
        case .moderate: return 0.10
        case .full: return 0.20
        }
    }

    var detail: String {
        switch self {
        case .off: return "Trust logged portions exactly as entered."
        case .conservative: return "Add 5% to logged food for mild portion underestimation."
        case .moderate: return "Add 10% to logged food for typical portion underestimation."
        case .full: return "Add 20% to logged food for heavy portion underestimation."
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, cardioMachine = "cardio_machine"
    var id: String { rawValue }
    var label: String {
        self == .cardioMachine ? "Cardio Machine" : rawValue.capitalized
    }
}

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core, fullBody = "full_body", cardio
    var id: String { rawValue }
    var label: String { self == .fullBody ? "Full Body" : rawValue.capitalized }
}
