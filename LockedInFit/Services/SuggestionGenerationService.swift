import Foundation

/// Rule-based suggestion generation after face/body check-ins. Suggestions are
/// specific and tied to detected signals; nothing shame-based, no crash advice,
/// and never a cut recommendation when leanness is already low.
enum SuggestionGenerationService {

    struct Context {
        var settings: UserSettings?
        var goal: Goal?
        var todaySodiumMg: Double = 0
        var sodiumLimitMg: Double = 2300
        /// Completed workouts in the last 28 days.
        var recentWorkoutCount: Int = 0
    }

    // MARK: - Face

    static func faceSuggestions(result: AppearanceScoringService.FaceScoreResult,
                                metrics: FacePhotoMetrics,
                                checkIn: AppearanceCheckIn,
                                history: [AppearanceCheckIn],
                                context: Context) -> [AppearanceSuggestion] {
        var out: [AppearanceSuggestion] = []
        let id = checkIn.uuid

        if result.quality < 12 {
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: "Retake tomorrow's photo in window light",
                explanation: metrics.meanLuminance < 0.3
                    ? "Today's photo is underexposed, which lowers comparison confidence."
                    : "Today's photo quality (sharpness/framing) limits how well it compares to your history.",
                expectedImpact: "Cleaner score trend and higher confidence.",
                category: .photoQuality, priority: 1, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        if metrics.yawDegrees > 15 || metrics.rollDegrees > 15 {
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: "Shoot straight-on at eye level",
                explanation: "Today's photo is angled, which distorts the symmetry and puffiness proxies.",
                expectedImpact: "More comparable photos day to day.",
                category: .photoQuality, priority: 2, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        if result.puffiness < 10 {
            let sodiumHigh = context.todaySodiumMg > context.sodiumLimitMg
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: "Take tomorrow's photo before caffeine or a salty breakfast",
                explanation: sodiumHigh
                    ? "Face reads puffier than your baseline and today's sodium (\(Int(context.todaySodiumMg)) mg) is over your \(Int(context.sodiumLimitMg)) mg limit; morning timing plus lower sodium gives a cleaner read."
                    : "Face reads puffier than your baseline. Morning photos before food and caffeine remove the biggest confounders.",
                expectedImpact: "Cleaner puffiness tracking.",
                category: sodiumHigh ? .nutrition : .photoQuality, priority: 2,
                durationType: .shortTerm, destination: .checklist, relatedCheckInId: id))
        }

        if result.skin < 14 {
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: "Add sunscreen to your morning checklist",
                explanation: "Skin-region readings vary a lot in your photos. Daily SPF is the single highest-evidence skin habit, independent of what the camera shows.",
                expectedImpact: "Long-run skin quality; steadier skin component.",
                category: .skin, priority: 2, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        if result.grooming < 11 {
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: "Schedule a haircut every 4 weeks",
                explanation: "Face visibility/grooming reads inconsistent across recent photos. A standing grooming cadence keeps it maintained without thinking about it.",
                expectedImpact: "Consistent grooming component; one less decision.",
                category: .grooming, priority: 3, durationType: .longTerm,
                destination: .calendar, relatedCheckInId: id))
        }

        if result.trend < 8 {
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: "Turn on the daily face-photo reminder",
                explanation: "Your check-in consistency is low, and every comparison-based component gets noisier with gaps.",
                expectedImpact: "Better baseline, higher-confidence scores.",
                category: .photoQuality, priority: 3, durationType: .shortTerm,
                destination: .saveOnly, relatedCheckInId: id))
        }

        // Sleep angle only when puffiness AND consistency both flag; a real pattern, not filler.
        if result.puffiness < 9 && result.trend >= 8 {
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: "Hold a consistent sleep window this week",
                explanation: "Puffiness is up against your baseline while photo timing is consistent; short or irregular sleep is the usual remaining driver.",
                expectedImpact: "Less morning puffiness; better recovery.",
                category: .sleep, priority: 3, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        return prioritize(out)
    }

    // MARK: - Body

    static func bodySuggestions(result: AppearanceScoringService.BodyScoreResult,
                                checkIn: AppearanceCheckIn,
                                context: Context) -> [AppearanceSuggestion] {
        var out: [AppearanceSuggestion] = []
        let id = checkIn.uuid
        let phase = context.goal?.phase

        if result.leannessGuard || phase == .maintain || phase == .leanBulk {
            if result.leannessGuard {
                out.append(AppearanceSuggestion(
                    sourceKind: "body",
                    title: "Do not cut further: bias toward lean mass and strength",
                    explanation: "Your composition data says leanness is not the limiter. Pushing lower costs muscle, sleep quality, and recovery for no visual return.",
                    expectedImpact: "Better long-term physique and health than more cutting.",
                    category: .body, priority: 1, durationType: .longTerm,
                    destination: .saveOnly, relatedCheckInId: id))
            }
            if context.recentWorkoutCount < 8 {
                out.append(AppearanceSuggestion(
                    sourceKind: "body",
                    title: "Add 3 hypertrophy sessions per week",
                    explanation: "Training volume is the biggest available lever for your physique right now (\(context.recentWorkoutCount) sessions in the last 4 weeks).",
                    expectedImpact: "Lean mass, posture, and the muscularity component.",
                    category: .workout, priority: 1, durationType: .longTerm,
                    destination: .workoutSchedule, relatedCheckInId: id))
            }
        } else if result.training < 8 {
            out.append(AppearanceSuggestion(
                sourceKind: "body",
                title: "Build a 3-day training schedule",
                explanation: "Training consistency is the lowest-scoring component that's fully under your control.",
                expectedImpact: "Moves composition, posture, and strength together.",
                category: .workout, priority: 1, durationType: .longTerm,
                destination: .workoutSchedule, relatedCheckInId: id))
        }

        if result.compositionLimited {
            out.append(AppearanceSuggestion(
                sourceKind: "body",
                title: "Log a body fat estimate",
                explanation: "Body scoring is running composition-limited. A smart-scale or caliper estimate, even a rough one, unlocks the composition and lean-mass components.",
                expectedImpact: "Higher-confidence body score.",
                category: .body, priority: 2, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        if result.photoPosture < 10 {
            out.append(AppearanceSuggestion(
                sourceKind: "body",
                title: "Retake body photos in the same spot and lighting",
                explanation: "Photo coverage or quality is limiting visual comparison. Same location, same time of day, phone propped at the same height.",
                expectedImpact: "Comparison confidence goes up immediately.",
                category: .photoQuality, priority: 2, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        if context.recentWorkoutCount >= 8 {
            out.append(AppearanceSuggestion(
                sourceKind: "body",
                title: "Add a 5-minute posture reset on training days",
                explanation: "You're training consistently; a short wall-slide/chin-tuck reset after sessions is a cheap add-on that shows up in photos.",
                expectedImpact: "Standing posture in photos and day to day.",
                category: .posture, priority: 3, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        if result.trendDirection < 5, let phase {
            out.append(AppearanceSuggestion(
                sourceKind: "body",
                title: "Tighten nutrition consistency for two weeks",
                explanation: "Weight trend is moving against your \(phase.label.lowercased()) goal. Two weeks of logged meals usually finds the leak without any drastic change.",
                expectedImpact: "Trend direction back in line with your goal.",
                category: .nutrition, priority: 2, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        return prioritize(out)
    }

    /// Sort by priority, keep 3–6.
    private static func prioritize(_ suggestions: [AppearanceSuggestion]) -> [AppearanceSuggestion] {
        Array(suggestions.sorted { $0.priority < $1.priority }.prefix(6))
    }

    /// Merge AI-generated suggestions into a rule-based list, dropping duplicates
    /// by title similarity and re-capping at 6.
    static func merge(local: [AppearanceSuggestion], ai: [AppearanceSuggestion]) -> [AppearanceSuggestion] {
        var result = local
        for candidate in ai {
            let duplicate = result.contains {
                $0.title.lowercased().hasPrefix(candidate.title.lowercased().prefix(18))
            }
            if !duplicate { result.append(candidate) }
        }
        return Array(result.sorted { $0.priority < $1.priority }.prefix(6))
    }
}
