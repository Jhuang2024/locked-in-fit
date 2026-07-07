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

    /// Every branch here is about the person, never the photo — no lighting,
    /// framing, angle, or "retake the photo" suggestions. Only genuine
    /// subject signals drive these (puffiness vs personal baseline, logged
    /// grooming/sleep behavior via `result`).
    static func faceSuggestions(result: AppearanceScoringService.FaceScoreResult,
                                checkIn: AppearanceCheckIn,
                                history: [AppearanceCheckIn],
                                context: Context) -> [AppearanceSuggestion] {
        var out: [AppearanceSuggestion] = []
        let id = checkIn.uuid

        // Puffiness: the actionable fix is the real driver (sodium or sleep), not photo timing.
        if result.puffiness < 13 {
            let sodiumHigh = context.todaySodiumMg > context.sodiumLimitMg
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: sodiumHigh ? "Cut evening sodium this week" : "Prioritize a consistent sleep window this week",
                explanation: sodiumHigh
                    ? "Face reads puffier than your baseline and today's sodium (\(Int(context.todaySodiumMg)) mg) is over your \(Int(context.sodiumLimitMg)) mg limit — sodium is the fastest lever on facial water retention."
                    : "Face reads puffier than your baseline. Sleep and hydration are the most common drivers of day-to-day facial puffiness.",
                expectedImpact: "Less puffiness, cleaner trend.",
                category: sodiumHigh ? .nutrition : .sleep, priority: 2,
                durationType: .shortTerm, destination: .checklist, relatedCheckInId: id))
        }

        if result.skin < 18 {
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: "Add sunscreen to your morning checklist",
                explanation: "Daily SPF is the single highest-evidence skin habit available, independent of anything a photo can show.",
                expectedImpact: "Long-run skin quality; steadier skin component.",
                category: .skin, priority: 2, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        if result.grooming < 15 {
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: "Schedule a haircut every 4 weeks",
                explanation: "Grooming/looks checklist items are due but incomplete. A standing grooming cadence keeps it maintained without thinking about it.",
                expectedImpact: "Consistent grooming component; one less decision.",
                category: .grooming, priority: 3, durationType: .longTerm,
                destination: .calendar, relatedCheckInId: id))
        }

        // Sleep angle only when puffiness AND consistency both flag — a real pattern, not filler.
        if result.puffiness < 12 && result.trend >= 8 {
            out.append(AppearanceSuggestion(
                sourceKind: "face",
                title: "Hold a consistent sleep window this week",
                explanation: "Puffiness is up against your baseline while your check-in consistency is solid — short or irregular sleep is the usual remaining driver.",
                expectedImpact: "Less morning puffiness; better recovery.",
                category: .sleep, priority: 3, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        return prioritize(out)
    }

    // MARK: - Body

    /// Every branch here is about the person — composition, training,
    /// posture, nutrition — never photo coverage/lighting/spot consistency.
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

        if context.recentWorkoutCount >= 8 {
            out.append(AppearanceSuggestion(
                sourceKind: "body",
                title: "Add a 5-minute posture reset on training days",
                explanation: "You're training consistently; a short wall-slide/chin-tuck reset after sessions is a cheap add-on that shows up in photos.",
                expectedImpact: "Standing posture in photos and day to day.",
                category: .posture, priority: 3, durationType: .shortTerm,
                destination: .checklist, relatedCheckInId: id))
        }

        if result.trendDirection < 8, let phase {
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

    // MARK: - Dedup against already-saved suggestions

    /// Collapses whitespace/punctuation/case so "Add sunscreen!" and
    /// "add   sunscreen." key the same. Used to compare freshly generated
    /// suggestions against ones already stored, regardless of scan history.
    static func normalizedKey(title: String, category: AppearanceSuggestionCategory) -> String {
        let folded = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "\(category.rawValue)|\(folded)"
    }

    /// Splits freshly generated suggestions into ones to insert and ones that
    /// duplicate a live (pending/approved/completed) suggestion — those get
    /// their explanation/impact/related check-in refreshed on the existing
    /// row instead of creating a second copy. Rejected suggestions don't
    /// count as live, so a rule that was dismissed can resurface later.
    static func reconcile(drafts: [AppearanceSuggestion],
                          existing: [AppearanceSuggestion]) -> (toInsert: [AppearanceSuggestion], toRefresh: [(AppearanceSuggestion, AppearanceSuggestion)]) {
        var existingByKey: [String: AppearanceSuggestion] = [:]
        for suggestion in existing where suggestion.status != .rejected {
            existingByKey[normalizedKey(title: suggestion.title, category: suggestion.category)] = suggestion
        }

        var toInsert: [AppearanceSuggestion] = []
        var toRefresh: [(AppearanceSuggestion, AppearanceSuggestion)] = []
        var seenThisBatch = Set<String>()

        for draft in drafts {
            let key = normalizedKey(title: draft.title, category: draft.category)
            guard !seenThisBatch.contains(key) else { continue }
            seenThisBatch.insert(key)

            if let match = existingByKey[key] {
                toRefresh.append((match, draft))
            } else {
                toInsert.append(draft)
            }
        }
        return (toInsert, toRefresh)
    }
}
