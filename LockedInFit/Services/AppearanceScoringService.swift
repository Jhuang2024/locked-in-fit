import Foundation

/// Local, deterministic appearance scoring. Scores measure photo quality,
/// consistency, grooming/visibility proxies, body-composition data, and
/// self-comparison against the user's own history; never objective
/// attractiveness, and never protected traits.
enum AppearanceScoringService {

    // MARK: - Face

    struct FaceScoreResult {
        /// 0–100.
        var total: Double
        /// Component points out of their weights: quality/20, skin/20,
        /// symmetry/15, grooming/15, puffiness/15, trend/15.
        var quality: Double
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

    static func scoreFace(metrics: FacePhotoMetrics,
                          history: [AppearanceCheckIn],
                          date: Date = .now) -> FaceScoreResult {
        var explanations: [String] = []

        // Photo quality (20): sharpness + exposure + face size + angle.
        let sharpnessPart = clamp((metrics.sharpness - 15) / 85) * 8          // 0–8
        let exposurePart = (1 - clamp(abs(metrics.meanLuminance - 0.5) / 0.35)) * 6 // 0–6
        let sizePart = clamp(metrics.faceAreaFraction / 0.12) * 3             // 0–3
        let anglePart = (1 - clamp(max(metrics.yawDegrees, metrics.rollDegrees) / 30)) * 3 // 0–3
        let quality = sharpnessPart + exposurePart + sizePart + anglePart
        if quality < 12 {
            explanations.append("Photo quality is holding the score down; lighting, sharpness, or framing could be better.")
        } else {
            explanations.append("Photo quality is solid: sharp, well-lit, and framed for comparison.")
        }

        // Skin/complexion proxy (20): evenness of face-region luminance.
        // High std dev = harsh shadows or uneven texture in this photo; a proxy, not dermatology.
        let evenness = 1 - clamp((metrics.faceLuminanceStdDev - 0.08) / 0.22)
        let skin = 8 + evenness * 12 // floor of 8: a single photo can't judge skin harshly
        explanations.append(evenness > 0.6
            ? "Skin-region lighting reads even in this shot."
            : "Face lighting is uneven; could be shadows or the light source, so this component is a rough proxy.")

        // Symmetry/landmark balance proxy (15): mostly a framing/pose signal.
        let symmetry = 6 + metrics.landmarkSymmetry * 9 // floored: pose noise dominates this proxy
        if metrics.landmarkSymmetry < 0.4 {
            explanations.append("Landmark balance is off; usually a head-tilt or angle issue, not your face.")
        }

        // Grooming/visibility proxy (15): how much of the face Vision could map.
        let grooming = 5 + metrics.landmarkCompleteness * 10
        if metrics.landmarkCompleteness < 0.7 {
            explanations.append("Parts of the face were hard to map (hair, glasses, or angle). Full visibility scores higher.")
        }

        // Puffiness/leanness proxy (15): today's face width/height ratio vs the
        // user's own history. No history → neutral score, lower confidence.
        var puffiness = 11.0
        var puffinessComparable = false
        let priorRatios = history
            .filter { $0.kind == .face && $0.faceWidthHeightRatio > 0 }
            .map(\.faceWidthHeightRatio)
        if metrics.widthHeightRatio > 0, priorRatios.count >= 3 {
            let baseline = median(priorRatios)
            let delta = (metrics.widthHeightRatio - baseline) / baseline
            // Wider than personal baseline reads puffier; leaner reads slightly better.
            puffiness = clamp(1 - max(0, delta) / 0.06) * 4 + 11 * clamp(1 - abs(delta) / 0.10)
            puffiness = max(4, min(15, puffiness))
            puffinessComparable = true
            if delta > 0.03 {
                explanations.append("Face reads slightly puffier than your recent baseline; salt, sleep, or photo timing can all cause this.")
            } else if delta < -0.02 {
                explanations.append("Face reads leaner than your recent baseline.")
            } else {
                explanations.append("Puffiness is in line with your recent baseline.")
            }
        } else {
            explanations.append("Puffiness tracking needs a few check-ins to build your personal baseline; neutral for now.")
        }

        // Consistency/streak/trend (15): check-in days in the last 14.
        let streak = faceStreak(history: history, endingAt: date)
        let daysWithCheckIns = Set(history.filter { $0.kind == .face && $0.date > date.daysAgo(14) }
            .map { $0.date.startOfDay }).count
        let trend = clamp(Double(daysWithCheckIns + 1) / 10) * 10 + clamp(Double(streak) / 7) * 5
        if streak >= 3 {
            explanations.append("\(streak)-day check-in streak; consistency is what makes these scores meaningful.")
        } else {
            explanations.append("Check in on more days to raise the consistency component and sharpen comparisons.")
        }

        // Confidence: photo quality dominates; history depth helps.
        var confidence = 0.35 + (quality / 20) * 0.4
        confidence += puffinessComparable ? 0.15 : 0.0
        confidence += min(0.1, Double(priorRatios.count) * 0.01)
        confidence = clamp(confidence)
        if quality < 10 {
            explanations.append("Confidence is reduced because photo quality limits comparison. Retaking in better light helps more than anything.")
        }

        let total = min(100, quality + skin + symmetry + grooming + puffiness + trend)
        return FaceScoreResult(total: total, quality: quality, skin: skin, symmetry: symmetry,
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
        var photoCount: Int
        /// Mean photo quality 0–1 from validation, if photos were validated.
        var photoQuality: Double
    }

    struct BodyScoreResult {
        var total: Double
        /// Component points: composition/40, leanMass/15, training/15, photoPosture/15, trendDirection/10, quality/5.
        var composition: Double
        var leanMass: Double
        var training: Double
        var photoPosture: Double
        var trendDirection: Double
        var quality: Double
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

        // Body photo/posture/proportion proxy (15): photo coverage-based.
        let photoPosture = 5 + clamp(Double(inputs.photoCount) / 3) * 7 + inputs.photoQuality * 3
        if inputs.photoCount == 0 {
            explanations.append("No body photos attached; the visual component is minimal. Front/side/back photos give the full picture.")
        } else if inputs.photoCount < 3 {
            explanations.append("Partial photo set (\(inputs.photoCount)/3). Adding the missing angles improves comparison.")
        }

        // Trend direction vs active goal (10).
        var trendDirection = 6.0
        if let rate = WeightTrendCalculator.weeklyChangeFromEntries(entries: inputs.weights), let goal = inputs.goal {
            let target = goal.weeklyWeightChangeTarget
            if abs(target) < 0.05 {
                trendDirection = (abs(rate) < 0.2 ? 10 : 5)
                explanations.append(abs(rate) < 0.2 ? "Weight is holding steady, matching your maintain goal." : "Weight is drifting despite a maintain goal.")
            } else if rate.sign == target.sign && abs(rate) >= abs(target) * 0.4 {
                trendDirection = 10
                explanations.append("Weight trend is moving in your goal's direction at a sensible rate.")
            } else if rate.sign == target.sign {
                trendDirection = 7
                explanations.append("Weight trend matches your goal's direction but slowly.")
            } else {
                trendDirection = 3
                explanations.append("Weight trend is moving against your active goal.")
            }
        } else {
            explanations.append("Trend component is neutral; it needs a weight trend and an active goal.")
        }

        // Photo quality (5).
        let quality = inputs.photoCount > 0 ? 1 + inputs.photoQuality * 4 : 1

        var confidence = 0.35
        if !compositionLimited { confidence += 0.25 }
        if heightValid { confidence += 0.1 }
        if inputs.photoCount >= 2 { confidence += 0.15 }
        if inputs.latestWeightKg != nil { confidence += 0.1 }
        confidence = clamp(confidence)

        let total = min(100, composition + leanMass + training + photoPosture + trendDirection + quality)
        return BodyScoreResult(total: total, composition: composition, leanMass: leanMass,
                               training: training, photoPosture: photoPosture,
                               trendDirection: trendDirection, quality: quality,
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
            photoQuality: 0)
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

    // MARK: - Small math helpers

    static func clamp(_ value: Double) -> Double { max(0, min(1, value)) }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
