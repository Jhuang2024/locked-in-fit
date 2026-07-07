import Foundation
import SwiftData

/// Builds full weekly training schedules on top of the existing one-off
/// WorkoutGeneratorService exercise library. The old generate(request:) path
/// is untouched; this adds template-driven multi-session planning.
enum WorkoutScheduleGeneratorService {

    struct ScheduleRequest {
        var goal: WorkoutScheduleGoal = .generalFitness
        var experience: WorkoutExperienceLevel = .intermediate
        var daysPerWeek: Int = 3
        var sessionLengthMinutes: Int = 60
        var equipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable, .bodyweight]
        /// Calendar weekdays (1 = Sunday ... 7 = Saturday), count == daysPerWeek ideally.
        var preferredWeekdays: [Int] = []
        var targetMuscles: Set<MuscleGroup> = []
        var limitations: String = ""
        var startDate: Date = .now
        /// Time of day for sessions (used for reminders/calendar events).
        var sessionHour: Int = 17
        var sessionMinute: Int = 0
        var syncToCalendar: Bool = false
    }

    /// One session's focus within the weekly split.
    enum SessionFocus: String {
        case fullBodyA = "Full Body A"
        case fullBodyB = "Full Body B"
        case fullBodyC = "Full Body C"
        case push = "Push"
        case pull = "Pull"
        case legs = "Legs"
        case upper = "Upper Body"
        case lower = "Lower Body"

        var patterns: [MovementPattern] {
            switch self {
            case .fullBodyA: return [.squat, .horizontalPush, .horizontalPull, .core]
            case .fullBodyB: return [.hinge, .verticalPush, .verticalPull, .core]
            case .fullBodyC: return [.squat, .horizontalPush, .hinge, .horizontalPull, .core]
            case .push: return [.horizontalPush, .verticalPush, .horizontalPush, .verticalPush, .core]
            case .pull: return [.verticalPull, .horizontalPull, .horizontalPull, .verticalPull, .core]
            case .legs: return [.squat, .hinge, .squat, .hinge, .core]
            case .upper: return [.horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .core]
            case .lower: return [.squat, .hinge, .squat, .core]
            }
        }

        var workoutType: WorkoutType {
            switch self {
            case .fullBodyA, .fullBodyB, .fullBodyC: return .fullBody
            case .push, .pull, .legs: return .pushPullLegs
            case .upper, .lower: return .upperLower
            }
        }
    }

    /// Weekly split templates: 2 = Full Body A/B, 3 = FB A/B/C or PPL,
    /// 4 = Upper/Lower ×2, 5 = PPL + Upper/Lower, 6 = PPL ×2.
    static func split(daysPerWeek: Int, experience: WorkoutExperienceLevel) -> [SessionFocus] {
        switch daysPerWeek {
        case ...2: return [.fullBodyA, .fullBodyB]
        case 3: return experience == .beginner
            ? [.fullBodyA, .fullBodyB, .fullBodyC]
            : [.push, .pull, .legs]
        case 4: return [.upper, .lower, .upper, .lower]
        case 5: return [.push, .pull, .legs, .upper, .lower]
        default: return [.push, .pull, .legs, .push, .pull, .legs]
        }
    }

    // MARK: - Generation

    static func generate(request: ScheduleRequest) -> WorkoutSchedule {
        let focuses = split(daysPerWeek: request.daysPerWeek, experience: request.experience)
        let weekdays = resolvedWeekdays(request: request, count: focuses.count)

        let schedule = WorkoutSchedule(
            title: scheduleTitle(for: request),
            goal: request.goal,
            experience: request.experience,
            daysPerWeek: focuses.count,
            sessionLengthMinutes: request.sessionLengthMinutes,
            equipment: Array(request.equipment),
            preferredWeekdays: weekdays,
            startDate: request.startDate,
            syncToCalendar: request.syncToCalendar,
            limitations: request.limitations,
            progressionNote: progressionNote(for: request))

        var usedThisWeek: [String: Int] = [:] // name → times used across the week
        let calendar = Calendar.current

        for (index, focus) in focuses.enumerated() {
            let weekday = weekdays[index % weekdays.count]
            let plan = sessionPlan(focus: focus, request: request, usedThisWeek: &usedThisWeek)

            var firstDate = Weekday.nextOccurrence(of: weekday, from: request.startDate)
            var timeComponents = calendar.dateComponents([.year, .month, .day], from: firstDate)
            timeComponents.hour = request.sessionHour
            timeComponents.minute = request.sessionMinute
            firstDate = calendar.date(from: timeComponents) ?? firstDate

            let session = WorkoutScheduleSession(
                weekday: weekday,
                date: firstDate,
                title: focus.rawValue,
                workoutType: focus.workoutType,
                estimatedDurationMinutes: request.sessionLengthMinutes,
                plannedExercises: plan)
            schedule.sessions?.append(session)
        }
        return schedule
    }

    /// Fill weekdays: use preferences first, then spread remaining sessions
    /// across free days with rest days in between where possible.
    private static func resolvedWeekdays(request: ScheduleRequest, count: Int) -> [Int] {
        var days = request.preferredWeekdays.filter { (1...7).contains($0) }.sorted()
        if days.count > count { days = Array(days.prefix(count)) }
        // Sensible default orderings that space sessions out.
        let fallbackOrder: [Int] = [2, 5, 4, 7, 3, 6, 1] // Mon, Thu, Wed, Sat, Tue, Fri, Sun
        for candidate in fallbackOrder where days.count < count {
            if !days.contains(candidate) { days.append(candidate) }
        }
        return days.sorted()
    }

    private static func sessionPlan(focus: SessionFocus,
                                    request: ScheduleRequest,
                                    usedThisWeek: inout [String: Int]) -> [PlannedExercise] {
        var patterns = focus.patterns
        let maxExercises = max(3, min(patterns.count, request.sessionLengthMinutes / 9))
        patterns = Array(patterns.prefix(maxExercises))

        var plan: [PlannedExercise] = []
        var usedThisSession = Set<String>()

        for (slot, pattern) in patterns.enumerated() {
            var candidates = WorkoutGeneratorService.library.filter {
                $0.pattern == pattern &&
                request.equipment.contains($0.equipment) &&
                !usedThisSession.contains($0.name)
            }
            if !request.targetMuscles.isEmpty {
                let targeted = candidates.filter { !Set($0.muscles).isDisjoint(with: request.targetMuscles) }
                if !targeted.isEmpty { candidates = targeted }
            }
            guard !candidates.isEmpty else { continue }

            // Best remaining candidate: prefer exercises not yet used this week
            // (variety across sessions), then the biggest movement available.
            let ranked = candidates.sorted {
                let usesA = usedThisWeek[$0.name, default: 0]
                let usesB = usedThisWeek[$1.name, default: 0]
                if usesA != usesB { return usesA < usesB }
                return $0.priority > $1.priority
            }
            guard let pick = ranked.first else { continue }

            usedThisSession.insert(pick.name)
            usedThisWeek[pick.name, default: 0] += 1

            let isCompound = pick.priority >= 7 && slot < 2
            let s = Self.scheme(goal: request.goal, experience: request.experience, isCompound: isCompound)
            plan.append(PlannedExercise(
                name: pick.name,
                sets: s.sets,
                reps: s.reps,
                restSeconds: s.rest,
                targetRPE: s.rpe,
                equipmentRaw: pick.equipment.rawValue,
                patternRaw: pick.pattern.rawValue,
                musclesRaw: pick.muscles.map(\.rawValue),
                note: exerciseNote(goal: request.goal, isCompound: isCompound)))
        }
        return plan
    }

    private static func scheme(goal: WorkoutScheduleGoal,
                               experience: WorkoutExperienceLevel,
                               isCompound: Bool) -> (sets: Int, reps: Int, rest: Int, rpe: Double) {
        let volumeBump = experience == .advanced ? 1 : 0
        let volumeCut = experience == .beginner ? 1 : 0
        switch goal {
        case .strength:
            return isCompound ? (4 + volumeBump - volumeCut, 5, 180, 8.5) : (3, 8, 120, 8)
        case .muscleGain:
            return isCompound ? (4 - volumeCut, 8, 120, 8) : (3 + volumeBump, 12, 90, 8.5)
        case .fatLoss:
            return isCompound ? (3, 10, 90, 8) : (3, 12, 60, 8.5)
        case .maintenance:
            return isCompound ? (3, 6, 150, 7.5) : (2, 10, 90, 8)
        case .generalFitness:
            return isCompound ? (3, 8, 120, 7.5) : (3, 10, 90, 8)
        }
    }

    private static func exerciseNote(goal: WorkoutScheduleGoal, isCompound: Bool) -> String {
        switch goal {
        case .strength:
            return isCompound ? "Add 2.5 kg once all sets hit target reps with 1–2 in reserve." : "Support work — quality reps over load."
        case .muscleGain:
            return "Add a rep each session; add weight at the top of the rep range."
        case .fatLoss:
            return "Keep rest honest and load steady — the deficit does the fat loss, training keeps the muscle."
        case .maintenance:
            return "Hold current loads; effort ~2 reps in reserve."
        case .generalFitness:
            return isCompound ? "Progress load slowly once sets feel easy." : "Chase quality reps, not load."
        }
    }

    private static func progressionNote(for request: ScheduleRequest) -> String {
        var note: String
        switch request.goal {
        case .strength: note = "Progression: linear load — add 2.5 kg to a lift when every set hits target reps with 1–2 reps in reserve."
        case .muscleGain: note = "Progression: double progression — add reps to the top of the range, then add weight and drop back."
        case .fatLoss: note = "Progression: hold loads through the deficit; treat maintaining strength as winning."
        case .maintenance: note = "Progression: none required — consistency is the whole job."
        case .generalFitness: note = "Progression: add a rep or small load bump whenever a session feels comfortable."
        }
        if request.experience != .beginner {
            note += " Deload every 5–6 weeks: same movements, ~60% of normal sets, then resume."
        }
        if !request.limitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note += " Noted limitations: \(request.limitations). Swap any movement that aggravates them for a pain-free variation."
        }
        return note
    }

    private static func scheduleTitle(for request: ScheduleRequest) -> String {
        "\(request.goal.label) · \(request.daysPerWeek)×/week"
    }

    // MARK: - Session → Workout

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Find or create today's Workout for a session. Reuses an existing
    /// non-template workout created from this session today so tapping the
    /// dashboard card twice never duplicates.
    static func workout(for session: WorkoutScheduleSession,
                        existingWorkouts: [Workout],
                        context: ModelContext,
                        date: Date = .now) -> Workout {
        let todayKey = dayKeyFormatter.string(from: date)
        if session.generatedWorkoutId == todayKey,
           let existing = existingWorkouts.first(where: {
               !$0.isTemplate && $0.title == session.title && Calendar.current.isDate($0.date, inSameDayAs: date)
           }) {
            return existing
        }
        let workout = Workout(
            date: date,
            title: session.title,
            type: session.workoutType,
            duration: Double(session.estimatedDurationMinutes),
            notes: session.schedule?.progressionNote ?? "")
        for (index, planned) in session.plannedExercises.enumerated() {
            workout.exercises?.append(planned.makeExercise(order: index))
        }
        context.insert(workout)
        session.generatedWorkoutId = todayKey
        return workout
    }

    /// Sessions due today across active schedules.
    static func sessionsDue(schedules: [WorkoutSchedule], on date: Date = .now) -> [WorkoutScheduleSession] {
        let weekday = Calendar.current.component(.weekday, from: date)
        return schedules
            .filter { $0.isActive && $0.startDate.startOfDay <= date.startOfDay }
            .flatMap { $0.sessionList }
            .filter { $0.weekday == weekday }
    }

    /// Whether a session already has a completed workout today.
    static func isCompletedToday(session: WorkoutScheduleSession, workouts: [Workout], date: Date = .now) -> Bool {
        workouts.contains {
            $0.completed && !$0.isTemplate && $0.title == session.title &&
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }
}
