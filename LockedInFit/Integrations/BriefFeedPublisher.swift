import Foundation
import SwiftData

/// Builds and writes the brief feed for Brief (the morning-briefing app):
/// per-day summary lines for the last few days plus today's and tomorrow's
/// reminders. Rides along with the existing peer-bridge publish on dashboard
/// load/refresh, and is fail-silent the same way: a missing App Group
/// container, a failed fetch, or no data at all degrade to writing whatever
/// is available (an empty feed with just `generatedAt` is valid), never to
/// an error the UI has to handle.
///
/// Fetches happen here rather than at the call site so publishing stays one
/// line in DashboardView; every fetch is best-effort and independent, so one
/// failing never drops the rest of the feed.
enum BriefFeedPublisher {

    /// How many local days back the day summaries cover (today inclusive).
    private static let daySpan = 3
    /// Reminder cap, per the feed contract in the Brief repo's LINKED_APPS.md.
    private static let maxReminders = 12
    /// Per-day summary line cap, per the same contract.
    private static let maxLinesPerDay = 8

    /// Local calendar day key ("2026-07-13"). Same idiom as
    /// WorkoutScheduleGeneratorService.dayKeyFormatter: fixed format and
    /// POSIX locale for stable digits, current calendar/timezone so the day
    /// boundary is the user's own midnight.
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    @discardableResult
    static func publish(modelContext: ModelContext, now: Date = .now) -> Bool {
        // Best-effort fetches, matching the repo's `(try? fetch) ?? []` idiom:
        // any individual failure reads as "no data of that kind" and the feed
        // is built from whatever remains.
        let completedWorkouts = (try? modelContext.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.completed && !$0.isTemplate }))) ?? []
        let meals = (try? modelContext.fetch(FetchDescriptor<MealLog>())) ?? []
        let sleepLogs = (try? modelContext.fetch(FetchDescriptor<SleepLog>())) ?? []
        let steps = (try? modelContext.fetch(FetchDescriptor<StepEntry>())) ?? []
        let activeEnergy = (try? modelContext.fetch(FetchDescriptor<ActiveEnergyEntry>())) ?? []
        let weights = (try? modelContext.fetch(FetchDescriptor<BodyWeightEntry>())) ?? []
        let checkIns = (try? modelContext.fetch(FetchDescriptor<AppearanceCheckIn>())) ?? []
        let checklistItems = (try? modelContext.fetch(FetchDescriptor<DailyChecklistItem>())) ?? []
        let schedules = (try? modelContext.fetch(FetchDescriptor<WorkoutSchedule>())) ?? []
        let goal = (try? modelContext.fetch(FetchDescriptor<Goal>(
            predicate: #Predicate<Goal> { $0.active })))?.first

        let feed = LockedInFitBriefFeed(
            generatedAt: now,
            days: days(now: now,
                       workouts: completedWorkouts,
                       meals: meals,
                       sleepLogs: sleepLogs,
                       steps: steps,
                       activeEnergy: activeEnergy,
                       weights: weights,
                       checkIns: checkIns,
                       checklistItems: checklistItems,
                       goal: goal),
            reminders: reminders(now: now,
                                 checklistItems: checklistItems,
                                 schedules: schedules,
                                 completedWorkouts: completedWorkouts))
        return SharedContextStore.writeBriefFeed(feed)
    }

    // MARK: - Day summaries

    private static func days(now: Date,
                             workouts: [Workout],
                             meals: [MealLog],
                             sleepLogs: [SleepLog],
                             steps: [StepEntry],
                             activeEnergy: [ActiveEnergyEntry],
                             weights: [BodyWeightEntry],
                             checkIns: [AppearanceCheckIn],
                             checklistItems: [DailyChecklistItem],
                             goal: Goal?) -> [LockedInFitBriefFeed.Day] {
        // Today first, then yesterday, then the day before: Brief's
        // "yesterday" section matches on the day key, so ordering is for
        // determinism and human inspection, not lookup.
        (0..<daySpan).compactMap { offset -> LockedInFitBriefFeed.Day? in
            let day = now.daysAgo(offset)
            let dayLines = lines(forDay: day,
                                 workouts: workouts,
                                 meals: meals,
                                 sleepLogs: sleepLogs,
                                 steps: steps,
                                 activeEnergy: activeEnergy,
                                 weights: weights,
                                 checkIns: checkIns,
                                 checklistItems: checklistItems,
                                 goal: goal)
            guard !dayLines.isEmpty else { return nil }
            return LockedInFitBriefFeed.Day(
                date: dayKeyFormatter.string(from: day),
                lines: Array(dayLines.prefix(maxLinesPerDay)))
        }
    }

    /// One local day's summary lines, most important first: workouts, then
    /// nutrition, sleep, steps, weight, appearance check-ins, checklist.
    private static func lines(forDay day: Date,
                              workouts: [Workout],
                              meals: [MealLog],
                              sleepLogs: [SleepLog],
                              steps: [StepEntry],
                              activeEnergy: [ActiveEnergyEntry],
                              weights: [BodyWeightEntry],
                              checkIns: [AppearanceCheckIn],
                              checklistItems: [DailyChecklistItem],
                              goal: Goal?) -> [String] {
        let calendar = Calendar.current
        var lines: [String] = []

        // 1. Workouts completed that day. Sorted by time then title so
        // repeated writes never shuffle the feed.
        let dayWorkouts = workouts
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { ($0.date, $0.title) < ($1.date, $1.title) }
        for workout in dayWorkouts {
            let name = workout.title.isEmpty ? "workout" : workout.title
            var details: [String] = []
            if workout.duration > 0 { details.append("\(Int(workout.duration.rounded())) min") }
            let exerciseCount = workout.exerciseList.count
            if exerciseCount > 0 {
                details.append("\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")")
            }
            if workout.caloriesBurned > 0 { details.append("\(grouped(workout.caloriesBurned)) kcal") }
            lines.append(details.isEmpty
                ? "Completed \(name)"
                : "Completed \(name) · " + details.joined(separator: ", "))
        }

        // 2. Nutrition: same day-sum calculator the dashboard uses, so the
        // brief never disagrees with the app about what was eaten.
        let dayMealCount = meals.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
        if dayMealCount > 0 {
            let nutrition = DailyNutritionCalculator.summary(for: day, meals: meals)
            var line = "\(dayMealCount) meal\(dayMealCount == 1 ? "" : "s") logged · "
                + "\(grouped(nutrition.calories)) kcal, \(grouped(nutrition.protein)) g protein"
            if let goal {
                line += " (target \(grouped(goal.calorieTarget)) / \(grouped(goal.proteinTarget)))"
            }
            lines.append(line)
        }

        // 3. Sleep: the night grouped under this day (SleepLog.date is the
        // day sleep began). Latest by createdAt when a night was re-logged,
        // matching the dashboard's sort.
        if let sleep = sleepLogs
            .filter({ calendar.isDate($0.date, inSameDayAs: day) })
            .max(by: { $0.createdAt < $1.createdAt }) {
            if sleep.durationHours > 0 {
                lines.append("Slept \(Formatters.trimmed(sleep.durationHours))h · sleep score \(Int(sleep.totalScore.rounded()))")
            } else {
                lines.append("Sleep score \(Int(sleep.totalScore.rounded()))")
            }
        }

        // 4. Steps (with active energy when present) and weigh-ins.
        if let stepEntry = steps
            .filter({ calendar.isDate($0.date, inSameDayAs: day) })
            .max(by: { $0.date < $1.date }), stepEntry.steps > 0 {
            var line = "\(stepEntry.steps.formatted()) steps"
            if let stepTarget = goal?.stepTarget { line += " (goal \(stepTarget.formatted()))" }
            if let energy = activeEnergy
                .filter({ calendar.isDate($0.date, inSameDayAs: day) })
                .max(by: { $0.date < $1.date }), energy.calories > 0 {
                line += " · \(grouped(energy.calories)) kcal active"
            }
            lines.append(line)
        }
        if let weighIn = weights
            .filter({ calendar.isDate($0.date, inSameDayAs: day) })
            .max(by: { $0.date < $1.date }) {
            lines.append("Weighed in at \(Formatters.kg(weighIn.weightKg))")
        }

        // 5. Appearance check-ins and checklist completion.
        let dayKinds = Set(checkIns
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .map(\.kind))
        if dayKinds.contains(.face) && dayKinds.contains(.body) {
            lines.append("Face and body check-ins done")
        } else if dayKinds.contains(.face) {
            lines.append("Face check-in done")
        } else if dayKinds.contains(.body) {
            lines.append("Body check-in done")
        }

        let dueThatDay = DailyChecklistService.dueItems(checklistItems, on: day)
        if !dueThatDay.isEmpty {
            let done = dueThatDay.filter { DailyChecklistService.isCompleted($0, on: day) }.count
            lines.append("Checklist \(done)/\(dueThatDay.count) done")
        }

        return lines
    }

    // MARK: - Reminders

    private static func reminders(now: Date,
                                  checklistItems: [DailyChecklistItem],
                                  schedules: [WorkoutSchedule],
                                  completedWorkouts: [Workout]) -> [LockedInFitBriefFeed.Reminder] {
        let calendar = Calendar.current
        let today = now.startOfDay
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let windowEnd = calendar.date(byAdding: .day, value: 2, to: today) else { return [] }
        var reminders: [LockedInFitBriefFeed.Reminder] = []

        // Checklist items, reusing DailyChecklistService so the feed's idea
        // of "due" matches the Today card and the peer-bridge publish
        // exactly. Items here have no specific time of day, so every
        // occurrence is all-day at local midnight of its day.
        for item in checklistItems {
            if item.recurrence == .none {
                // One-time: a single entry with its real due day. Overdue
                // uses the same test as DashboardView's crossAppPublishInput.
                guard !item.isCompleted, item.dueDate.startOfDay <= windowEnd else { continue }
                reminders.append(LockedInFitBriefFeed.Reminder(
                    id: item.uuid,
                    title: item.title,
                    detail: item.details.isEmpty ? nil : item.details,
                    dueDate: item.dueDate.startOfDay,
                    isAllDay: true,
                    overdue: item.dueDate.startOfDay < today))
            } else {
                // Recurring: today's occurrence if still open, plus a
                // projection for tomorrow (the feed is usually written the
                // evening before the brief is read). Occurrence ids carry
                // the day key so the two never collide and stay stable
                // across writes.
                if DailyChecklistService.isDue(item, on: now), !DailyChecklistService.isCompleted(item, on: now) {
                    reminders.append(occurrence(of: item, on: today))
                }
                if DailyChecklistService.isDue(item, on: tomorrow) {
                    reminders.append(occurrence(of: item, on: tomorrow))
                }
            }
        }

        // Scheduled workout sessions today and tomorrow, due at the
        // session's own time of day. Today's session drops out once a
        // completed workout exists for it.
        for day in [today, tomorrow] {
            for session in WorkoutScheduleGeneratorService.sessionsDue(schedules: schedules, on: day) {
                if calendar.isDate(day, inSameDayAs: today),
                   WorkoutScheduleGeneratorService.isCompletedToday(session: session, workouts: completedWorkouts, date: day) {
                    continue
                }
                let dueDate = sessionTime(session, on: day)
                reminders.append(LockedInFitBriefFeed.Reminder(
                    id: "\(session.uuid)@\(dayKeyFormatter.string(from: day))",
                    title: session.title,
                    detail: "Scheduled workout, ~\(session.estimatedDurationMinutes) min",
                    dueDate: dueDate,
                    isAllDay: false,
                    overdue: dueDate < now))
            }
        }

        // Overdue first, then soonest due; id as the final tiebreaker so
        // repeated writes are byte-for-byte stable.
        reminders.sort { a, b in
            if a.overdue != b.overdue { return a.overdue }
            if a.dueDate != b.dueDate { return a.dueDate < b.dueDate }
            return a.id < b.id
        }
        return Array(reminders.prefix(maxReminders))
    }

    /// A recurring checklist item's occurrence on a specific day. Recurring
    /// items are never "overdue": they reset daily rather than accumulating,
    /// matching the peer-bridge publish's convention.
    private static func occurrence(of item: DailyChecklistItem, on day: Date) -> LockedInFitBriefFeed.Reminder {
        LockedInFitBriefFeed.Reminder(
            id: "\(item.uuid)@\(dayKeyFormatter.string(from: day))",
            title: item.title,
            detail: item.details.isEmpty ? nil : item.details,
            dueDate: day.startOfDay,
            isAllDay: true,
            overdue: false)
    }

    /// The session's time of day placed on `day`. Sessions store their time
    /// on `date` (the first occurrence); a nil date falls back to the
    /// generator's default 17:00.
    private static func sessionTime(_ session: WorkoutScheduleSession, on day: Date) -> Date {
        let calendar = Calendar.current
        let time = session.date.map { calendar.dateComponents([.hour, .minute], from: $0) }
        return calendar.date(bySettingHour: time?.hour ?? 17,
                             minute: time?.minute ?? 0,
                             second: 0,
                             of: day) ?? day.startOfDay
    }

    /// Whole-number kcal/gram figures with locale grouping ("2,150"), never
    /// raw decimals.
    private static func grouped(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}
