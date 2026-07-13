import Foundation

/// Local, deterministic appearance scoring. Scores judge the subject, never
/// the photo and never system/data limitations. Background, lighting,
/// sharpness, camera angle, resolution, framing, missing history, disabled
/// AI, and thin logs play no part in any score component: a photo either
/// passes FacePhotoValidator's usability gate (in which case it's scored) or
/// it's blocked before scoring ever runs, and any component that lacks real
/// data falls back to a neutral value instead of being penalized. What's
/// scored: self-comparison against the user's own history, logged
/// grooming/sleep behavior, and body-composition data, never objective
/// attractiveness, and never protected traits. Every result carries a
/// separate `confidenceNotes` list for data-quality/tracking caveats so they
/// never get mixed into the "why this score" explanations.
enum AppearanceScoringService {

    // MARK: - Face

    struct FaceScoreResult {
        /// 0–100.
        var total: Double
        /// Component points out of their weights: skin/30, symmetry/15,
        /// grooming/25, puffiness/30. Every point here is about the subject.
        /// There is no "consistency"/streak component: how often someone
        /// checks in is an app-engagement fact, not something about their
        /// face, so it never contributes to the score. `symmetry` is a flat
        /// neutral value locally (no reliable local signal exists for it), so
        /// the achievable local total tops out at 95, not 100; AI analysis
        /// can move the total the rest of the way with a real visual read.
        var skin: Double
        var symmetry: Double
        var grooming: Double
        var puffiness: Double
        /// 0–1. How much to trust the number above, never a reason to raise
        /// or lower it.
        var confidence: Double
        /// "Why this score?" bullet lines, strictly about the subject:
        /// what's happening with their skin, grooming, or puffiness.
        var explanations: [String]
        /// Confidence/data-quality/tracking notes: photo usability, missing
        /// history, disabled AI, thin logs. Never affects `total`, `skin`,
        /// `symmetry`, `grooming`, or `puffiness` above; shown in its own
        /// "Confidence & Tracking Notes" section, not mixed into `explanations`.
        var confidenceNotes: [String]
    }

    /// - Parameters:
    ///   - looksComplianceRatio: fraction of due `.looks`-category checklist
    ///     items completed recently (grooming/skincare habits). `nil` when
    ///     nothing's been tracked yet; treated as neutral, never as a penalty.
    ///   - sleepComplianceRatio: same, for `.sleep`-category checklist items.
    static func scoreFace(metrics: FacePhotoMetrics,
                          history: [AppearanceCheckIn],
                          looksComplianceRatio: Double? = nil,
                          sleepComplianceRatio: Double? = nil) -> FaceScoreResult {
        var explanations: [String] = []
        var confidenceNotes: [String] = []

        // Photo usability is a confidence signal only: it never adds to or
        // subtracts from the subject score below. Photos this rough are
        // already blocked before scoring by FacePhotoValidator; this just
        // measures how much residual noise a borderline-but-usable photo adds.
        let sharpnessPart = clamp((metrics.sharpness - 15) / 85)
        let exposurePart = 1 - clamp(abs(metrics.meanLuminance - 0.5) / 0.35)
        let anglePart = 1 - clamp(max(metrics.yawDegrees, metrics.rollDegrees) / 30)
        let photoUsability = (sharpnessPart + exposurePart + anglePart) / 3
        if photoUsability < 0.5 {
            confidenceNotes.append("Photo sharpness, lighting, or angle limits confidence in this reading, but never lowers the score itself.")
        }

        // Skin (30): lighting/luminance statistics measure the photo, not the
        // skin, so they play no part here. Neutral baseline, nudged only by
        // actual logged skincare and sleep behavior; missing data stays
        // neutral rather than penalizing.
        let skin = 16 + (looksComplianceRatio ?? 0.5) * 9 + (sleepComplianceRatio ?? 0.5) * 5
        if let looksComplianceRatio, looksComplianceRatio >= 0.7 {
            explanations.append("Recent skincare and grooming habits are keeping this steady.")
        } else if let looksComplianceRatio, looksComplianceRatio < 0.4 {
            explanations.append("Skincare and grooming habits have lapsed lately, which is holding this back.")
        } else if let sleepComplianceRatio, sleepComplianceRatio >= 0.7 {
            explanations.append("Consistent sleep is supporting the skin component.")
        }
        if looksComplianceRatio == nil && sleepComplianceRatio == nil {
            confidenceNotes.append("Skin stays neutral until skincare or sleep habits are logged.")
        }

        // Symmetry (15): a single 2D photo can't separate real facial symmetry
        // from head angle, so no photo metric is allowed to move this. It
        // stays a flat neutral value locally: a permanent, structural fact
        // about single-photo scoring, not a data gap the user can close, so
        // it's not repeated here as a confidence note every single check-in.
        let symmetry = 10.0

        // Grooming (25): a habit, not a pixel statistic; tied to actual
        // grooming/looks-checklist follow-through. Missing data stays
        // neutral rather than penalizing.
        let grooming = 11 + (looksComplianceRatio ?? 0.5) * 14
        if let looksComplianceRatio, looksComplianceRatio >= 0.7 {
            explanations.append("Grooming habits are being kept up consistently.")
        } else if let looksComplianceRatio, looksComplianceRatio < 0.4 {
            explanations.append("Grooming habits have lapsed, which is the fastest lever here.")
        }
        if looksComplianceRatio == nil {
            confidenceNotes.append("No grooming or skincare habit data logged yet; approve a suggestion to start tracking this.")
        }

        // Puffiness/leanness proxy (30): today's face width/height ratio vs the
        // user's own history, a real subject signal, self-compared so no
        // single photo's technical quality can skew it. No history → neutral,
        // never penalized.
        var puffiness = 22.0
        var puffinessComparable = false
        let priorRatios = history
            .filter { $0.kind == .face && $0.faceWidthHeightRatio > 0 }
            .map(\.faceWidthHeightRatio)
        if metrics.widthHeightRatio > 0, priorRatios.count >= 3 {
            let baseline = median(priorRatios)
            let delta = (metrics.widthHeightRatio - baseline) / baseline
            // Wider than personal baseline reads puffier; leaner reads slightly better.
            puffiness = clamp(1 - max(0, delta) / 0.06) * 8 + 22 * clamp(1 - abs(delta) / 0.10)
            puffiness = max(8, min(30, puffiness))
            puffinessComparable = true
            if delta > 0.03 {
                explanations.append("Face reads puffier than your recent baseline. Salt, sleep, or hydration are the usual drivers.")
            } else if delta < -0.02 {
                explanations.append("Face reads leaner than your recent baseline.")
            } else {
                explanations.append("Puffiness is in line with your recent baseline.")
            }
        } else {
            confidenceNotes.append("Puffiness needs 3+ prior check-ins to build a personal baseline; neutral until then, not penalized.")
        }

        // Confidence: how much to trust the number, never used to lower the
        // score itself. Reflects measurement usability, history depth, and
        // how much logged-behavior data is backing the skin/grooming components.
        var confidence = 0.4 + photoUsability * 0.25
        confidence += puffinessComparable ? 0.15 : 0.0
        confidence += min(0.1, Double(priorRatios.count) * 0.01)
        confidence += (looksComplianceRatio != nil || sleepComplianceRatio != nil) ? 0.1 : 0
        confidence = clamp(confidence)

        let total = min(100, skin + symmetry + grooming + puffiness)
        return FaceScoreResult(total: total, skin: skin, symmetry: symmetry,
                               grooming: grooming, puffiness: puffiness,
                               confidence: confidence, explanations: explanations,
                               confidenceNotes: confidenceNotes)
    }

    /// Consecutive days ending today/yesterday with at least one face check-in.
    static func faceStreak(history: [AppearanceCheckIn], endingAt date: Date = .now) -> Int {
        let days = Set(history.filter { $0.kind == .face }.map { $0.date.startOfDay })
        guard !days.isEmpty else { return 0 }
        var cursor = date.startOfDay
        if !days.contains(cursor) {
            // Streak can survive until today's photo is taken.
            cursor = cursor.daysAgo(1)
            guard days.contains(cursor) else { return 0 }
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = cursor.daysAgo(1)
        }
        return streak
    }

    // MARK: - Body

    struct BodyScoreInputs {
        var latestWeightKg: Double?
        var latestBodyFatPercent: Double?
        var heightCm: Double?
        var sex: BiologicalSex
        var goal: Goal?
        /// Completed, non-template workouts (recent history).
        var workouts: [Workout]
        var weights: [BodyWeightEntry]
        /// How many of front/side/back are present: a coverage signal, not a
        /// technical-quality one.
        var photoCount: Int
        /// Days in the last 14 where the protein target was hit, out of days
        /// with any meal logged. `nil` when there isn't enough logged data to
        /// mean anything. Insight-only: connects nutrition to the composition
        /// narrative without folding into the numeric score.
        var recentProteinHitDays: Int?
        var recentProteinTrackedDays: Int?
    }

    struct BodyScoreResult {
        var total: Double
        /// Component points: composition/40, leanMass/15, training/15, posture/15, trendDirection/15.
        /// `posture` is a flat neutral value locally (no reliable local
        /// signal exists for it, same reasoning as face `symmetry`), so the
        /// achievable local total tops out at 95, not 100.
        var composition: Double
        var leanMass: Double
        var training: Double
        var posture: Double
        var trendDirection: Double
        /// 0–1. How much to trust the number above, never a reason to raise
        /// or lower it.
        var confidence: Double
        /// "Why this score?" bullet lines, strictly about the subject.
        var explanations: [String]
        /// Confidence/data-quality/tracking notes: missing body fat, missing
        /// photos, missing goal/weight-trend data. Never affects the
        /// components above; shown in its own section, not mixed into
        /// `explanations`.
        var confidenceNotes: [String]
        /// True when body fat data is missing and composition scoring is degraded.
        var compositionLimited: Bool
        /// True when leanness is already low; cutting must NOT be suggested.
        var leannessGuard: Bool
    }

    static func scoreBody(inputs: BodyScoreInputs, date: Date = .now) -> BodyScoreResult {
        var explanations: [String] = []
        var confidenceNotes: [String] = []
        var compositionLimited = false
        var leannessGuard = false

        let heightValid = (inputs.heightCm ?? 0) > 120 && (inputs.heightCm ?? 0) < 230

        // Body composition (40).
        var composition = 22.0 // neutral midpoint when data is missing, never penalized
        if let bf = inputs.latestBodyFatPercent, bf > 2, bf < 60 {
            composition = compositionPoints(bodyFat: bf, sex: inputs.sex)
            let floorBF: Double = inputs.sex == .male ? 8 : 16
            if bf <= floorBF {
                leannessGuard = true
                explanations.append("Body fat is already very low. Further cutting is off the table: the lever now is muscle, sleep, and recovery.")
            } else {
                explanations.append("Composition scored from your logged body fat (\(Formatters.trimmed(bf))%).")
            }
        } else {
            compositionLimited = true
            confidenceNotes.append("No body fat data logged, so composition stays at a neutral value instead of being penalized. Log body fat for a real signal.")
        }

        // Low weight-for-height guard (BMI < 18.5) also blocks cut advice.
        if let weight = inputs.latestWeightKg, heightValid, let height = inputs.heightCm {
            let bmi = weight / pow(height / 100, 2)
            if bmi < 18.5 {
                leannessGuard = true
                explanations.append("Weight is low for your height. Building lean mass matters far more than any cut.")
            }
        }

        // Lean mass / FFMI proxy (15): needs weight, body fat, and height.
        var leanMass = 10.5
        if let weight = inputs.latestWeightKg, let bf = inputs.latestBodyFatPercent,
           heightValid, let height = inputs.heightCm, bf > 2, bf < 60 {
            let heightM = height / 100
            let ffm = weight * (1 - bf / 100)
            let ffmi = ffm / (heightM * heightM) + 6.1 * (1.8 - heightM)
            // ~16 low → ~22+ well-muscled (natural range), scaled for sex.
            let low: Double = inputs.sex == .male ? 16 : 13
            let high: Double = inputs.sex == .male ? 22 : 18
            leanMass = clamp((ffmi - low) / (high - low)) * 15
            explanations.append("Lean-mass index (FFMI proxy) is \(Formatters.trimmed(ffmi)), rewarding muscle, not just lightness.")
        } else {
            confidenceNotes.append("Lean-mass component is neutral: it needs weight, body fat, and height together.")
        }

        // Training consistency (15): completed sessions in the last 28 days vs
        // ~12. This is real training behavior, not app-engagement, so an
        // actual absence of workouts is a genuine (low) signal, not missing data.
        let recentWorkouts = inputs.workouts.filter { $0.completed && !$0.isTemplate && $0.date > date.daysAgo(28) }.count
        let training = clamp(Double(recentWorkouts) / 12) * 15
        explanations.append(recentWorkouts == 0
            ? "No completed workouts in the last 4 weeks: training consistency is the fastest component to move."
            : "\(recentWorkouts) workouts completed in the last 4 weeks.")

        // Posture (15): a single photo can't reliably read posture any more
        // than it can read facial symmetry, so this stays a flat neutral
        // value locally regardless of photo count: a permanent, structural
        // fact, not a data gap, so it's not repeated as a confidence note on
        // its own. Photo count is still worth flagging when photos are
        // missing entirely, since front/side/back angles are what the rest
        // of the app (comparisons, AI observations) actually uses.
        let posture = 10.0
        if inputs.photoCount == 0 {
            confidenceNotes.append("No body photos attached yet. Front/side/back photos help track changes over time.")
        }

        // Trend direction vs active goal (15).
        var trendDirection = 9.0
        if let rate = WeightTrendCalculator.weeklyChangeFromEntries(entries: inputs.weights), let goal = inputs.goal {
            let target = goal.weeklyWeightChangeTarget
            if abs(target) < 0.05 {
                trendDirection = (abs(rate) < 0.2 ? 15 : 7)
                explanations.append(abs(rate) < 0.2 ? "Weight is holding steady, matching your maintain goal." : "Weight is drifting despite a maintain goal.")
            } else if rate.sign == target.sign && abs(rate) >= abs(target) * 0.4 {
                trendDirection = 15
                explanations.append("Weight trend is moving in your goal's direction at a sensible rate.")
            } else if rate.sign == target.sign {
                trendDirection = 10
                explanations.append("Weight trend matches your goal's direction but slowly.")
            } else {
                trendDirection = 4
                explanations.append("Weight trend is moving against your active goal.")
            }
        } else {
            confidenceNotes.append("Trend component is neutral: it needs a weight trend and an active goal.")
        }

        // Nutrition connection: about the subject's logged behavior, not a
        // system limitation, so it lives in explanations rather than confidenceNotes.
        if let hit = inputs.recentProteinHitDays, let tracked = inputs.recentProteinTrackedDays, tracked > 0 {
            let ratio = Double(hit) / Double(tracked)
            explanations.append(ratio >= 0.7
                ? "Protein target hit on \(hit)/\(tracked) recently logged days: nutrition is backing up this composition trend."
                : "Protein target was only hit on \(hit)/\(tracked) recently logged days: nutrition consistency is the fastest lever on composition.")
        }

        var confidence = 0.35
        if !compositionLimited { confidence += 0.25 }
        if heightValid { confidence += 0.1 }
        if inputs.photoCount >= 2 { confidence += 0.15 }
        if inputs.latestWeightKg != nil { confidence += 0.1 }
        if inputs.recentProteinTrackedDays != nil { confidence += 0.05 }
        confidence = clamp(confidence)

        let total = min(100, composition + leanMass + training + posture + trendDirection)
        return BodyScoreResult(total: total, composition: composition, leanMass: leanMass,
                               training: training, posture: posture,
                               trendDirection: trendDirection,
                               confidence: confidence, explanations: explanations,
                               confidenceNotes: confidenceNotes,
                               compositionLimited: compositionLimited, leannessGuard: leannessGuard)
    }

    /// A body score computed from composition data alone (weight, body fat,
    /// height, training, trend) with no body photo required. Returns nil only
    /// when there is no weight or body fat logged at all; otherwise a body
    /// score always exists, just composition-limited/lower-confidence when
    /// some inputs are missing.
    static func liveBodyScore(weights: [BodyWeightEntry], bodyFats: [BodyFatEntry],
                              workouts: [Workout], settings: UserSettings?, goal: Goal?,
                              date: Date = .now) -> BodyScoreResult? {
        guard weights.last != nil || bodyFats.last != nil else { return nil }
        let heightLooksDefault = (settings?.heightCm ?? 0) <= 0 || settings?.heightCm == 175
        let inputs = BodyScoreInputs(
            latestWeightKg: weights.last?.weightKg,
            latestBodyFatPercent: bodyFats.last?.bodyFatPercentage,
            heightCm: heightLooksDefault ? nil : settings?.heightCm,
            sex: settings?.sex ?? .male,
            goal: goal,
            workouts: workouts,
            weights: weights,
            photoCount: 0,
            recentProteinHitDays: nil,
            recentProteinTrackedDays: nil)
        return scoreBody(inputs: inputs, date: date)
    }

    /// Composition points out of 40. Peaks across a healthy-athletic band and
    /// deliberately does NOT reward pushing below essential/low body fat.
    private static func compositionPoints(bodyFat: Double, sex: BiologicalSex) -> Double {
        let idealLow: Double = sex == .male ? 10 : 18
        let idealHigh: Double = sex == .male ? 16 : 25
        let floor: Double = sex == .male ? 8 : 16
        if bodyFat < floor {
            // Below the healthy floor: hold at the plateau, never higher;
            // extra leanness is not rewarded.
            return 36
        }
        if bodyFat <= idealHigh && bodyFat >= idealLow { return 40 }
        if bodyFat < idealLow { return 38 } // between floor and ideal band
        // Above ideal band: taper down to 12 at +20 percentage points.
        let over = bodyFat - idealHigh
        return max(12, 40 - over * 1.4)
    }

    // MARK: - Combined

    /// Combined appearance score from the latest face and body check-ins,
    /// weighting each by recency (a 60-day-old score fades out).
    static func combinedScore(face: AppearanceCheckIn?, body: AppearanceCheckIn?, date: Date = .now) -> Double? {
        func recencyWeight(_ checkIn: AppearanceCheckIn?) -> Double {
            guard let checkIn else { return 0 }
            let age = date.timeIntervalSince(checkIn.date) / 86400
            return max(0, 1 - age / 60)
        }
        let faceWeight = recencyWeight(face)
        let bodyWeight = recencyWeight(body)
        guard faceWeight + bodyWeight > 0 else { return nil }
        let sum = (face?.totalScore ?? 0) * faceWeight + (body?.totalScore ?? 0) * bodyWeight
        return sum / (faceWeight + bodyWeight)
    }

    /// The body score to display: the latest saved body check-in if there is
    /// one, otherwise the live composition-only score. Shared by every screen
    /// that shows a body score so they never disagree with each other.
    static func effectiveBodyScore(checkIn: AppearanceCheckIn?, live: BodyScoreResult?) -> Double? {
        checkIn?.totalScore ?? live?.total
    }

    /// Combined score for display when there may be no saved body check-in
    /// yet. Falls back to `combinedScore` when a real body check-in exists;
    /// otherwise blends the face score (recency-weighted, as above) with the
    /// live composition score (always full weight, since it reflects today's
    /// data). Shared so the Dashboard widget and the Looks page always agree.
    static func combinedScore(face: AppearanceCheckIn?, body: AppearanceCheckIn?,
                              liveBody: BodyScoreResult?, date: Date = .now) -> Double? {
        if body != nil { return combinedScore(face: face, body: body, date: date) }
        guard let bodyScore = liveBody?.total else { return combinedScore(face: face, body: nil, date: date) }
        guard let face else { return bodyScore }
        let age = date.timeIntervalSince(face.date) / 86400
        let faceWeight = max(0, 1 - age / 60)
        guard faceWeight > 0 else { return bodyScore }
        return (face.totalScore * faceWeight + bodyScore) / (faceWeight + 1)
    }

    // MARK: - Small math helpers

    static func clamp(_ value: Double) -> Double { max(0, min(1, value)) }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
