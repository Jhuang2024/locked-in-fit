import Foundation
import SwiftData

/// Gamified 0–1000 strength scores per movement pattern.
/// Considers bodyweight-relative strength, recent progress, volume, and consistency.
enum StrengthScoreCalculator {

    static let levels: [(threshold: Double, name: String)] = [
        (0, "Untrained"),
        (150, "Novice"),
        (300, "Developing"),
        (450, "Intermediate"),
        (600, "Advanced"),
        (750, "Elite"),
        (900, "Locked In")
    ]

    static func levelName(for score: Double) -> String {
        levels.last(where: { score >= $0.threshold })?.name ?? "Untrained"
    }

    static func epley1RM(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// 1RM-to-bodyweight ratio that maps to a score of 1000 per pattern.
    /// Intermediate lifters land mid-scale.
    private static func eliteRatio(for pattern: MovementPattern) -> Double {
        switch pattern {
        case .squat: return 2.25
        case .hinge: return 2.75
        case .horizontalPush: return 1.6
        case .verticalPush: return 1.1
        case .horizontalPull: return 1.6
        case .verticalPull: return 1.5 // weighted pull-up total / BW
        case .core: return 1.0
        case .conditioning: return 1.0
        }
    }

    /// Difficulty multiplier so machine/cable work doesn't score like free barbell work.
    private static func difficultyFactor(for equipment: Equipment) -> Double {
        switch equipment {
        case .barbell: return 1.0
        case .dumbbell: return 1.05 // DBs are harder per kg
        case .bodyweight: return 1.0
        case .kettlebell: return 1.0
        case .machine: return 0.85
        case .cable: return 0.88
        case .band: return 0.7
        case .cardioMachine: return 1.0
        }
    }

    struct MovementStats {
        var best1RM: Double = 0
        var bestSetSummary: String = ""
        var volume30d: Double = 0
        var volumePrev30d: Double = 0
        var sessionsLast30d: Int = 0
        var weeklyStreak: Int = 0
        var best1RM30dAgo: Double = 0
    }

    /// Recompute all pattern scores from completed workout history.
    static func recompute(workouts: [Workout], bodyWeightKg: Double, existing: [StrengthScore], context: ModelContext) {
        let completed = workouts.filter { $0.completed && !$0.isTemplate }
        var statsByPattern: [MovementPattern: MovementStats] = [:]
        let now = Date()
        let cutoff30 = now.daysAgo(30)
        let cutoff60 = now.daysAgo(60)

        for workout in completed {
            for exercise in workout.exerciseList {
                let pattern = exercise.movementPattern
                var stats = statsByPattern[pattern] ?? MovementStats()
                let factor = difficultyFactor(for: exercise.equipment)
                for set in exercise.setList where set.completed {
                    // Bodyweight movements count bodyweight as load.
                    let load = exercise.equipment == .bodyweight ? bodyWeightKg + set.weight : set.weight
                    let oneRM = epley1RM(weight: load * factor, reps: set.reps)
                    if oneRM > stats.best1RM {
                        stats.best1RM = oneRM
                        stats.bestSetSummary = "\(exercise.name): \(Int(set.weight)) kg × \(set.reps)"
                    }
                    if workout.date <= cutoff30, oneRM > stats.best1RM30dAgo {
                        stats.best1RM30dAgo = oneRM
                    }
                    let volume = load * Double(set.reps)
                    if workout.date > cutoff30 {
                        stats.volume30d += volume
                    } else if workout.date > cutoff60 {
                        stats.volumePrev30d += volume
                    }
                }
                if workout.date > cutoff30 { stats.sessionsLast30d += 1 }
                statsByPattern[pattern] = stats
            }
        }

        // Weekly consistency streak: consecutive weeks (back from this week) with ≥1 session of the pattern.
        for (pattern, var stats) in statsByPattern {
            stats.weeklyStreak = weeklyStreak(for: pattern, workouts: completed)
            statsByPattern[pattern] = stats
        }

        for pattern in MovementPattern.allCases {
            let stats = statsByPattern[pattern] ?? MovementStats()
            let score = score(for: pattern, stats: stats, bodyWeightKg: bodyWeightKg)
            let record = existing.first(where: { $0.movement == pattern }) ?? {
                let new = StrengthScore(movement: pattern)
                context.insert(new)
                return new
            }()
            record.trend = score - baseScore(for: pattern, best1RM: stats.best1RM30dAgo, bodyWeightKg: bodyWeightKg)
            record.score = score
            record.levelName = levelName(for: score)
            record.bestSetSummary = stats.bestSetSummary
            record.estimated1RM = stats.best1RM.rounded()
            record.volumeTrend = stats.volumePrev30d > 0 ? (stats.volume30d - stats.volumePrev30d) / stats.volumePrev30d : 0
            record.consistencyStreak = stats.weeklyStreak
            record.lastUpdated = .now
        }
    }

    private static func baseScore(for pattern: MovementPattern, best1RM: Double, bodyWeightKg: Double) -> Double {
        guard bodyWeightKg > 0, best1RM > 0 else { return 0 }
        let ratio = best1RM / bodyWeightKg
        return min(850, (ratio / eliteRatio(for: pattern)) * 850)
    }

    /// Base (0–850) from relative strength + up to 150 bonus from volume trend and consistency.
    static func score(for pattern: MovementPattern, stats: MovementStats, bodyWeightKg: Double) -> Double {
        let base = baseScore(for: pattern, best1RM: stats.best1RM, bodyWeightKg: bodyWeightKg)
        guard base > 0 else { return 0 }
        var bonus = 0.0
        bonus += min(60, Double(stats.weeklyStreak) * 10) // consistency
        if stats.volumePrev30d > 0, stats.volume30d > stats.volumePrev30d {
            bonus += min(40, (stats.volume30d / stats.volumePrev30d - 1) * 100)
        }
        if stats.best1RM30dAgo > 0, stats.best1RM > stats.best1RM30dAgo {
            bonus += min(50, (stats.best1RM / stats.best1RM30dAgo - 1) * 500) // recent progress
        }
        return min(1000, (base + bonus).rounded())
    }

    static func weeklyStreak(for pattern: MovementPattern, workouts: [Workout]) -> Int {
        let calendar = Calendar.current
        let weeksWithPattern: Set<Int> = Set(workouts.compactMap { workout in
            guard workout.exerciseList.contains(where: { $0.movementPattern == pattern }) else { return nil }
            return calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: workout.date).weekOfYear.map {
                $0 + (calendar.dateComponents([.yearForWeekOfYear], from: workout.date).yearForWeekOfYear ?? 0) * 100
            }
        })
        var streak = 0
        var probe = Date()
        while true {
            let comps = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: probe)
            let key = (comps.weekOfYear ?? 0) + (comps.yearForWeekOfYear ?? 0) * 100
            if weeksWithPattern.contains(key) {
                streak += 1
            } else if streak > 0 || probe < Date().daysAgo(7) {
                break
            }
            guard let earlier = calendar.date(byAdding: .weekOfYear, value: -1, to: probe) else { break }
            probe = earlier
            if streak > 104 { break }
        }
        return streak
    }

    /// Overall level: average of the top patterns the user actually trains.
    static func overallScore(scores: [StrengthScore]) -> Double {
        let trained = scores.filter { $0.score > 0 }
        guard !trained.isEmpty else { return 0 }
        return (trained.map(\.score).reduce(0, +) / Double(trained.count)).rounded()
    }
}
