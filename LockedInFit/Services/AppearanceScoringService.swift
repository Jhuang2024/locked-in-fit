import Foundation

/// Local, deterministic appearance scoring. Scores judge the subject — never
/// the photo. Background, lighting, sharpness, camera angle, resolution, and
/// framing play no part in any component below; a photo either passes
/// FacePhotoValidator's usability gate (in which case it's scored) or it's
/// blocked before scoring ever runs. What's scored: self-comparison against
/// the user's own history, logged grooming/sleep behavior, and body-
/// composition data — never objective attractiveness, and never protected
/// traits.
enum AppearanceScoringService {

    // MARK: - Face

    struct FaceScoreResult {
        /// 0–100.
        var total: Double
        /// Component points out of their weights: skin/25, symmetry/20,
        /// grooming/20, puffiness/20, trend/15. None of these are derived
        /// from photo-technical signals (lighting, sharpness, angle, etc).
        var skin: Double
        var symmetry: Double
        var grooming: Double
        var puffiness: Double
        var trend: Double
        /// 0–1.
        var confidence: Double
        /// "Why this score?" bullet lines.
        var explanations: [String]
    }

    /// - Parameters:
    ///   - looksComplianceRatio: fraction of due `.looks`-category checklist
    ///     items completed recently (grooming/skincare habits). `nil` when
    ///     nothing's been tracked yet — treated as neutral.
    ///   - sleepComplianceRatio: same, for `.sleep`-category checklist items.
    static func scoreFace(metrics: FacePhotoMetrics,
                          history: [AppearanceCheckIn],
                          looksComplianceRatio: Double? = nil,
                          sleepComplianceRatio: Double? = nil,
                          date: Date = .now) -> FaceScoreResult {
        var explanations: [String] = []

        // Photo usability is a confidence signal only — it never adds to or
        // subtracts from the subject score below. Photos this rough are
        // already blocked before scoring by FacePhotoValidator; this just
        // measures how much residual noise a borderline-but-usable photo adds.
        let sharpnessPart = clamp((metrics.sharpness - 15) / 85)
        let exposurePart = 1 - clamp(abs(metrics.meanLuminance - 0.5) / 0.35)
        let anglePart = 1 - clamp(max(metrics.yawDegrees, metrics.rollDegrees) / 30)
        let photoUsability = (sharpnessPart + exposurePart + anglePart) / 3

        // Skin (25): lighting/luminance statistics measure the photo, not the
        // skin, so they play no part here. Neutral baseline, nudged only by
        // actual logged skincare and sleep behavior.
        let skin = 13 + (looksComplianceRatio ?? 0.5) * 8 + (sleepComplianceRatio ?? 0.5) * 4
        if let looksComplianceRatio, looksComplianceRatio >= 0.7 {
            explanations.append("Recent skincare/grooming checklist consistency is feeding this component.")
        } else if let sleepComplianceRatio, sleepComplianceRatio >= 0.7 {
            explanations.append("Consistent sleep logging is feeding this component — sleep shows up in skin more than any photo setting.")
        } else {
            explanations.append("Skin can't be read from photo statistics alone — this stays neutral until skincare or sleep habits are logged, or AI analysis is enabled.")
        }

        // Symmetry (20): a single 2D photo can't separate real facial symmetry
        // from head angle, so no photo metric is allowed to move this. It
        // stays a flat neutral value locally; AI analysis, if enabled, can
        // give the total score a real visual read.
        let symmetry = 13.0
        explanations.append("Symmetry isn't reliably measurable from a single local photo — enable AI analysis in Settings for a real visual read.")

        // Grooming (20): a habit, not a pixel statistic — tied to actual
        // grooming/looks-checklist follow-through.
        let grooming = 9 + (looksComplianceRatio ?? 0.5) * 11
        if let looksComplianceRatio, looksComplianceRatio > 0 {
            explanations.append(looksComplianceRatio >= 0.7
                ? "Grooming/looks checklist items are getting done consistently."
                : "Grooming/looks checklist items are due but incomplete — that's the fastest lever here.")
        } else {
            explanations.append("No grooming/looks checklist history yet — approve a suggestion to start tracking this.")
        }

        // Puffiness/leanness proxy (20): today's face width/height ratio vs the
        // user's own history — a real subject signal, self-compared so no
        // single photo's technical quality can skew it. No history → neutral.
        var puffiness = 15.0
        var puffinessComparable = false
        let priorRatios = history
            .filter { $0.kind == .face && $0.faceWidthHeightRatio > 0 }
            .map(\.faceWidthHeightRatio)
        if metrics.widthHeightRatio > 0, priorRatios.count >= 3 {
            let baseline = median(priorRatios)
            let delta = (metrics.widthHeightRatio - baseline) / baseline
            // Wider than personal baseline reads puffier; leaner reads slightly better.
            puffiness = clamp(1 - max(0, delta) / 0.06) * 5 + 15 * clamp(1 - abs(delta) / 0.10)
            puffiness = max(5, min(20, puffiness))
            puffinessComparable = true
            if delta > 0.03 {
                explanations.append("Face reads slightly puffier than your recent baseline — salt, sleep, or hydration are the usual drivers.")
            } else if delta < -0.02 {
                explanations.append("Face reads leaner than your recent baseline.")
            } else {
                explanations.append("Puffiness is in line with your recent baseline.")
            }
        } else {
            explanations.append("Puffiness tracking needs a few check-ins to build your personal baseline; neutral for now.")
        }

        // Consistency/streak/trend (15): check-in days in the last 14 — pure behavior.
        let streak = faceStreak(history: history, endingAt: date)
        let daysWithCheckIns = Set(history.filter { $0.kind == .face && $0.date > date.daysAgo(14) }
            .map { $0.date.startOfDay }).count
        let trend = clamp(Double(daysWithCheckIns + 1) / 10) * 10 + clamp(Double(streak) / 7) * 5
        if streak >= 3 {
            explanations.append("\(streak)-day check-in streak; consistency is what makes these scores meaningful.")
        } else {
            explanations.append("Check in on more days to raise the consistency component and sharpen comparisons.")
        }

        // Confidence: how much to trust the number — never used to lower the
        // score itself. Reflects measurement usability, history depth, and
        // how much logged-behavior data is backing the skin/grooming components.
        var confidence = 0.4 + photoUsability * 0.25
        confidence += puffinessComparable ? 0.15 : 0.0
        confidence += min(0.1, Double(priorRatios.count) * 0.01)
        confidence += (looksComplianceRatio != nil || sleepComplianceRatio != nil) ? 0.1 : 0
        confidence = clamp(confidence)

        let total = min(100, skin + symmetry + grooming + puffiness + trend)
        return FaceScoreResult(total: total, skin: skin, symmetry: symmetry,
                               grooming: grooming, puffiness: puffiness, trend: trend,
                               confidence: confidence, explanations: explanations)
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
        /// How many of front/side/back are present — a coverage signal, not a
        /// technical-quality one.
        var photoCount: Int
        /// Days in the last 14 where the protein target was hit, out of days
        /// with any meal logged. `nil` when there isn't enough logged data to
        /// mean anything. Insight-only — connects nutrition to the composition
        /// narrative without folding into the numeric score.
        var recentProteinHitDays: Int?
        var recentProteinTrackedDays: Int?
    }

    struct BodyScoreResult {
        var total: Double
        /// Component points: composition/40, leanMass/15, training/15, photoPosture/15, trendDirection/15.
        var composition: Double
        var leanMass: Double
        var training: Double
        var photoPosture: Double
        var trendDirection: Double
        var confidence: Double
        var explanations: [String]
        /// True when body fat data is missing and composition scoring is degraded.
        var compositionLimited: Bool
        /// True when leanness is already low; cutting must NOT be suggested.
        var leannessGuard: Bool
    }

    static func scoreBody(inputs: BodyScoreInputs, date: Date = .now) -> BodyScoreResult {
        var explanations: [String] = []
        var compositionLimited = false
        var leannessGuard = false

        let heightValid = (inputs.heightCm ?? 0) > 120 && (inputs.heightCm ?? 0) < 230

        // Body composition (40).
        var composition = 22.0 // neutral midpoint when data is missing
        if let bf = inputs.latestBodyFatPercent, bf > 2, bf < 60 {
            composition = compositionPoints(bodyFat: bf, sex: inputs.sex)
            let floorBF: Double = inputs.sex == .male ? 8 : 16
            if bf <= floorBF {
                leannessGuard = true
                explanations.append("Body fat is already very low. Further cutting is off the table; the lever now is muscle, sleep, and recovery.")
            } else {
                explanations.append("Composition scored from your logged body fat (\(Formatters.trimmed(bf))%).")
            }
        } else {
            compositionLimited = true
            explanations.append("No body fat data; composition is scored at a neutral value (composition-limited). Log body fat for a real signal.")
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
        var leanMass = 8.0
        if let weight = inputs.latestWeightKg, let bf = inputs.latestBodyFatPercent,
           heightValid, let height = inputs.heightCm, bf > 2, bf < 60 {
            let heightM = height / 100
            let ffm = weight * (1 - bf / 100)
            let ffmi = ffm / (heightM * heightM) + 6.1 * (1.8 - heightM)
            // ~16 low → ~22+ well-muscled (natural range), scaled for sex.
            let low: Double = inputs.sex == .male ? 16 : 13
            let high: Double = inputs.sex == .male ? 22 : 18
            leanMass = clamp((ffmi - low) / (high - low)) * 15
            explanations.append("Lean-mass index (FFMI proxy) is \(Formatters.trimmed(ffmi)); this rewards muscle, not just lightness.")
        } else {
            explanations.append("Lean-mass component is neutral: it needs weight, body fat, and height together.")
        }

        // Training consistency (15): completed sessions in the last 28 days vs ~12.
        let recentWorkouts = inputs.workouts.filter { $0.completed && !$0.isTemplate && $0.date > date.daysAgo(28) }.count
        let training = clamp(Double(recentWorkouts) / 12) * 15
        explanations.append(recentWorkouts == 0
            ? "No completed workouts in the last 4 weeks; training consistency is the fastest component to move."
            : "\(recentWorkouts) workouts completed in the last 4 weeks.")

        // Body photo/posture coverage proxy (15): how many angles you have —
        // never how technically good those photos are.
        let photoPosture = 5 + clamp(Double(inputs.photoCount) / 3) * 10
        if inputs.photoCount == 0 {
            explanations.append("No body photos attached; the visual component is minimal. Front/side/back photos give the full picture.")
        } else if inputs.photoCount < 3 {
            explanations.append("Partial photo set (\(inputs.photoCount)/3). Adding the missing angles improves comparison.")
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
            explanations.append("Trend component is neutral; it needs a weight trend and an active goal.")
        }

        // Nutrition connection — insight only, doesn't move any component.
        if let hit = inputs.recentProteinHitDays, let tracked = inputs.recentProteinTrackedDays, tracked > 0 {
            let ratio = Double(hit) / Double(tracked)
            explanations.append(ratio >= 0.7
                ? "Protein target hit on \(hit)/\(tracked) recently logged days — nutrition is backing up this composition trend."
                : "Protein target was only hit on \(hit)/\(tracked) recently logged days — nutrition consistency is the fastest lever on composition.")
        }

        var confidence = 0.35
        if !compositionLimited { confidence += 0.25 }
        if heightValid { confidence += 0.1 }
        if inputs.photoCount >= 2 { confidence += 0.15 }
        if inputs.latestWeightKg != nil { confidence += 0.1 }
        if inputs.recentProteinTrackedDays != nil { confidence += 0.05 }
        confidence = clamp(confidence)

        let total = min(100, composition + leanMass + training + photoPosture + trendDirection)
        return BodyScoreResult(total: total, composition: composition, leanMass: leanMass,
                               training: training, photoPosture: photoPosture,
                               trendDirection: trendDirection,
                               confidence: confidence, explanations: explanations,
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
