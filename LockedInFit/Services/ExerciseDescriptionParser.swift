import Foundation

/// Everything needed to add one exercise to a workout, whether it came from a
/// library pick or a free-text description. The single currency of the unified
/// Add Exercise flow.
struct ExerciseDraft {
    var name: String
    var muscleGroups: [MuscleGroup]
    var movementPattern: MovementPattern
    var equipment: Equipment
    var setCount: Int
    var reps: Int
    /// kg, matching WorkoutSet storage. For dumbbell work this is per hand.
    var weightKg: Double
    /// True when the draft is (or exactly matched) a built-in library exercise.
    var matchedLibrary: Bool
    var notes: String = ""

    static func from(library exercise: LibraryExercise) -> ExerciseDraft {
        ExerciseDraft(name: exercise.name,
                      muscleGroups: exercise.muscles,
                      movementPattern: exercise.pattern,
                      equipment: exercise.equipment,
                      setCount: 1,
                      reps: 8,
                      weightKg: 0,
                      matchedLibrary: true)
    }

    var prescriptionSummary: String {
        var text = "\(setCount) set\(setCount == 1 ? "" : "s") × \(reps) reps"
        if weightKg > 0 {
            text += " @ \(Formatters.trimmed(weightKg)) kg"
        }
        return text
    }

    /// From an AI (or mock) ExerciseEstimate: maps its raw enum strings back
    /// with safe fallbacks, and re-checks the library so a name the model
    /// phrased slightly differently still resolves to the canonical entry.
    static func from(estimate: ExerciseEstimate) -> ExerciseDraft {
        let pattern = MovementPattern(rawValue: estimate.movementPattern) ?? .horizontalPush
        let equipment = Equipment(rawValue: estimate.equipment) ?? .dumbbell
        let muscles = estimate.muscleGroups.compactMap { MuscleGroup(rawValue: $0) }
        let sets = min(20, max(1, estimate.sets))
        let reps = min(100, max(1, estimate.reps))
        let weight = min(500, max(0, estimate.weightKg))

        if let library = ExerciseDescriptionParser.bestLibraryMatch(for: estimate.name) {
            return ExerciseDraft(name: library.name,
                                 muscleGroups: library.muscles,
                                 movementPattern: library.pattern,
                                 equipment: library.equipment,
                                 setCount: sets,
                                 reps: reps,
                                 weightKg: weight,
                                 matchedLibrary: true)
        }
        return ExerciseDraft(name: estimate.name.isEmpty ? "Custom Exercise" : estimate.name,
                             muscleGroups: muscles.isEmpty ? ExerciseDescriptionParser.inferMuscles(from: estimate.name.lowercased(), pattern: pattern) : muscles,
                             movementPattern: pattern,
                             equipment: equipment,
                             setCount: sets,
                             reps: reps,
                             weightKg: weight,
                             matchedLibrary: false)
    }
}

/// Turns a natural-language description like "incline dumbbell press, 3 sets,
/// 10 reps, 45 lb each hand" into an ExerciseDraft. Matches the built-in
/// library when the name maps cleanly; otherwise infers pattern/equipment/
/// muscles from keywords so the entry saves as a custom exercise without a
/// separate flow.
enum ExerciseDescriptionParser {

    static func parse(_ text: String, units: UnitSystem = .metric) -> ExerciseDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()

        var sets: Int?
        var reps: Int?
        var weightKg: Double?

        // "3x10" / "5 × 5".
        if let match = firstMatch(in: lowered, pattern: #"\b(\d{1,2})\s*[x×]\s*(\d{1,3})\b"#) {
            sets = Int(match[1])
            reps = Int(match[2])
        }
        if let match = firstMatch(in: lowered, pattern: #"(\d{1,2})\s*sets?\b"#) {
            sets = Int(match[1])
        }
        if let match = firstMatch(in: lowered, pattern: #"(\d{1,3})\s*reps?\b"#) {
            reps = Int(match[1])
        }
        // Weight with an explicit unit ("45 lb", "20kg", "45 lbs each hand").
        if let match = firstMatch(in: lowered, pattern: #"(\d+(?:\.\d+)?)\s*(kgs?|kilos?|kilograms?|lbs?|pounds?)\b"#) {
            let value = Double(match[1]) ?? 0
            weightKg = match[2].hasPrefix("k") ? value : value * 0.45359237
        } else if let match = firstMatch(in: lowered, pattern: #"(?:@|\bat)\s*(\d+(?:\.\d+)?)(?!\s*(?:reps?|sets?|min|[x×]))"#) {
            // "@ 225" with no unit: assume the user's unit system.
            let value = Double(match[1]) ?? 0
            weightKg = units == .imperial ? value * 0.45359237 : value
        }

        let name = cleanName(from: lowered)
        guard !name.isEmpty else { return nil }

        let clampedSets = min(20, max(1, sets ?? 3))
        let clampedReps = min(100, max(1, reps ?? 8))
        let clampedWeight = min(500, max(0, weightKg ?? 0))

        if let library = bestLibraryMatch(for: name) {
            return ExerciseDraft(name: library.name,
                                 muscleGroups: library.muscles,
                                 movementPattern: library.pattern,
                                 equipment: library.equipment,
                                 setCount: clampedSets,
                                 reps: clampedReps,
                                 weightKg: clampedWeight,
                                 matchedLibrary: true)
        }

        let pattern = inferPattern(from: lowered)
        return ExerciseDraft(name: titleCased(name),
                             muscleGroups: inferMuscles(from: lowered, pattern: pattern),
                             movementPattern: pattern,
                             equipment: inferEquipment(from: lowered),
                             setCount: clampedSets,
                             reps: clampedReps,
                             weightKg: clampedWeight,
                             matchedLibrary: false)
    }

    // MARK: - Name extraction

    /// Strips prescription phrases (sets/reps/weight) and filler words, leaving
    /// just the exercise name regardless of where the numbers appear.
    private static func cleanName(from lowered: String) -> String {
        var text = lowered
        let removePatterns = [
            #"\b\d{1,2}\s*[x×]\s*\d{1,3}\b"#,
            #"\d{1,2}\s*sets?\b"#,
            #"\d{1,3}\s*reps?\b"#,
            #"\d+(?:\.\d+)?\s*(?:kgs?|kilos?|kilograms?|lbs?|pounds?)\b"#,
            #"(?:@|\bat)\s*\d+(?:\.\d+)?\b"#,
            #"\b(?:each|per)\s+(?:hand|side|arm|leg|dumbbell)\b"#,
            #"\d+(?:\.\d+)?\s*(?:min|minutes?|sec|seconds?)\b"#,
        ]
        for pattern in removePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        }
        let fillers: Set<String> = ["for", "at", "with", "x", "of", "a", "an", "the",
                                    "did", "do", "doing", "some", "my", "and", "then"]
        let tokens = text
            .split(whereSeparator: { ",;.:\n".contains($0) || $0.isWhitespace })
            .map(String.init)
            .filter { !fillers.contains($0) && Double($0) == nil }
        return tokens.joined(separator: " ")
    }

    private static func titleCased(_ name: String) -> String {
        name.split(separator: " ").map { word in
            word.prefix(1).uppercased() + String(word.dropFirst())
        }.joined(separator: " ")
    }

    // MARK: - Library matching

    /// Exact (case-insensitive) name match, or a strong token overlap. Weak
    /// partial matches deliberately stay custom, per the "does not perfectly
    /// map" rule, so "cable pressdown" never hijacks "Bench Press".
    static func bestLibraryMatch(for name: String) -> LibraryExercise? {
        let lowered = name.lowercased()
        if let exact = WorkoutGeneratorService.library.first(where: { $0.name.lowercased() == lowered }) {
            return exact
        }
        let queryTokens = Set(lowered.split(separator: " ").map { normalizeToken(String($0)) })
        guard !queryTokens.isEmpty else { return nil }
        var best: (exercise: LibraryExercise, score: Double)?
        for exercise in WorkoutGeneratorService.library {
            let libraryTokens = Set(exercise.name.lowercased().split(separator: " ").map { normalizeToken(String($0)) })
            let overlap = Double(queryTokens.intersection(libraryTokens).count)
            guard overlap > 0 else { continue }
            let score = overlap / Double(queryTokens.union(libraryTokens).count)
            if score > (best?.score ?? 0) { best = (exercise, score) }
        }
        guard let best, best.score >= 0.75 else { return nil }
        return best.exercise
    }

    /// Singular, hyphen-free token so "push-ups" matches "Push-Up".
    private static func normalizeToken(_ token: String) -> String {
        var t = token.replacingOccurrences(of: "-", with: "")
        if t.count > 3, t.hasSuffix("s") { t = String(t.dropLast()) }
        return t
    }

    // MARK: - Inference for custom exercises

    static func inferEquipment(from text: String) -> Equipment {
        if contains(text, ["dumbbell", "db "]) { return .dumbbell }
        if contains(text, ["barbell", "bench press", "deadlift", "back squat"]) { return .barbell }
        if contains(text, ["cable", "pulldown", "pushdown"]) { return .cable }
        if contains(text, ["machine", "smith", "leg press", "leg extension", "leg curl"]) { return .machine }
        if contains(text, ["kettlebell", "kb "]) { return .kettlebell }
        if contains(text, ["band"]) { return .band }
        if contains(text, ["treadmill", "bike", "rowing", "erg", "elliptical", "stairmaster", "ski"]) { return .cardioMachine }
        if contains(text, ["push-up", "pushup", "pull-up", "pullup", "chin-up", "chinup", "dip",
                           "plank", "bodyweight", "burpee", "crunch", "run", "sprint", "walk"]) { return .bodyweight }
        return .dumbbell // most unnamed accessory work
    }

    static func inferPattern(from text: String) -> MovementPattern {
        if contains(text, ["squat", "lunge", "leg press", "step-up", "step up", "leg extension"]) { return .squat }
        if contains(text, ["deadlift", "rdl", "hip thrust", "swing", "good morning", "leg curl",
                           "hamstring", "glute", "hinge", "back extension"]) { return .hinge }
        if contains(text, ["run", "sprint", "jog", "bike", "cycling", "rowing", "erg", "swim",
                           "hiit", "cardio", "treadmill", "elliptical", "burpee", "jump rope", "walk"]) { return .conditioning }
        if contains(text, ["pulldown", "pull-up", "pullup", "chin-up", "chinup", "pull down"]) { return .verticalPull }
        if contains(text, ["row", "face pull", "rear delt", "curl", "bicep", "shrug"]) { return .horizontalPull }
        if contains(text, ["overhead press", "shoulder press", "ohp", "military press",
                           "lateral raise", "front raise", "arnold", "upright row"]) { return .verticalPush }
        if contains(text, ["crunch", "plank", "ab ", "abs", "core", "leg raise", "sit-up", "situp",
                           "stretch", "mobility", "yoga"]) { return .core }
        if contains(text, ["bench", "press", "push-up", "pushup", "chest", "fly", "flye", "dip",
                           "pushdown", "tricep", "extension", "skull"]) { return .horizontalPush }
        return .horizontalPush // model default; harmless for scoring
    }

    static func inferMuscles(from text: String, pattern: MovementPattern) -> [MuscleGroup] {
        var muscles: [MuscleGroup] = []
        if contains(text, ["chest", "bench", "fly", "flye", "push-up", "pushup"]) { muscles.append(.chest) }
        if contains(text, ["row", "pulldown", "pull-up", "pullup", "chin", "lat", "back extension", "shrug"]) { muscles.append(.back) }
        if contains(text, ["shoulder", "delt", "lateral raise", "front raise", "overhead", "ohp", "military"]) { muscles.append(.shoulders) }
        if contains(text, ["bicep", "curl"]) { muscles.append(.biceps) }
        if contains(text, ["tricep", "pushdown", "skull", "dip"]) { muscles.append(.triceps) }
        if contains(text, ["squat", "lunge", "leg press", "leg extension", "quad"]) { muscles.append(.quads) }
        if contains(text, ["deadlift", "rdl", "leg curl", "hamstring", "good morning"]) { muscles.append(.hamstrings) }
        if contains(text, ["glute", "hip thrust"]) { muscles.append(.glutes) }
        if contains(text, ["calf", "calves"]) { muscles.append(.calves) }
        if contains(text, ["ab ", "abs", "core", "crunch", "plank", "leg raise", "sit-up", "situp"]) { muscles.append(.core) }
        if !muscles.isEmpty { return muscles }
        switch pattern {
        case .squat: return [.quads, .glutes]
        case .hinge: return [.hamstrings, .glutes]
        case .horizontalPush: return [.chest, .triceps]
        case .verticalPush: return [.shoulders]
        case .horizontalPull: return [.back, .biceps]
        case .verticalPull: return [.back, .biceps]
        case .core: return [.core]
        case .conditioning: return [.cardio]
        }
    }

    // MARK: - Helpers

    private static func contains(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    /// Full match plus capture groups as strings; empty string for unmatched groups.
    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let r = Range(match.range(at: index), in: text) else { return "" }
            return String(text[r])
        }
    }
}
