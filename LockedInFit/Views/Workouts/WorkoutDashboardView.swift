import SwiftUI
import SwiftData
import Charts

struct WorkoutDashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query private var strengthScores: [StrengthScore]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]

    @Query(sort: \WorkoutSchedule.createdAt, order: .reverse) private var schedules: [WorkoutSchedule]

    @State private var showGenerator = false
    @State private var showScheduleGenerator = false
    @State private var activeWorkout: Workout?
    /// True when `activeWorkout` was just created via createBlankWorkout()
    /// and hasn't been saved yet. See WorkoutLogView's Cancel/Save toolbar.
    @State private var activeWorkoutIsDraft = false

    private var history: [Workout] { workouts.filter { !$0.isTemplate } }
    private var templates: [Workout] { workouts.filter(\.isTemplate) }
    private var completed: [Workout] { history.filter(\.completed) }

    private var activeSchedules: [WorkoutSchedule] { schedules.filter(\.isActive) }
    /// Next upcoming session across active schedules within the next 7 days.
    private var upcomingSession: (session: WorkoutScheduleSession, date: Date)? {
        let now = Date()
        return activeSchedules
            .flatMap { $0.sessionList }
            .map { session -> (session: WorkoutScheduleSession, date: Date) in
                let base = session.date ?? now
                var next = Weekday.nextOccurrence(of: session.weekday, from: now)
                // Carry the session's time of day onto the next occurrence.
                let time = Calendar.current.dateComponents([.hour, .minute], from: base)
                next = Calendar.current.date(bySettingHour: time.hour ?? 17, minute: time.minute ?? 0, second: 0, of: next) ?? next
                if next < now, let bumped = Calendar.current.date(byAdding: .day, value: 7, to: next) { next = bumped }
                return (session: session, date: next)
            }
            .min { $0.date < $1.date }
    }

    private var weeklyVolume: [(week: Date, volume: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: completed.filter { $0.date > Date().daysAgo(84) }) {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date.startOfDay
        }
        return grouped.map { (week: $0.key, volume: $0.value.reduce(0) { $0 + $1.totalVolume }) }
            .sorted { $0.week < $1.week }
    }

    private var overall: Double { StrengthScoreCalculator.overallScore(scores: strengthScores) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Button { showGenerator = true } label: {
                        Label("Workout", systemImage: "wand.and.stars")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { showScheduleGenerator = true } label: {
                        Label("Schedule", systemImage: "calendar.day.timeline.left")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    Button { createBlankWorkout() } label: {
                        Label("Blank", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }

                if let upcoming = upcomingSession {
                    upcomingSessionCard(upcoming.session, date: upcoming.date)
                }

                if !activeSchedules.isEmpty {
                    activeSchedulesCard
                }

                DashboardCard(title: "Overall Strength", systemImage: "trophy") {
                    if strengthScores.isEmpty {
                        EmptyStateView(systemImage: "trophy", title: "No strength scores yet", message: "Complete workouts with logged sets to build your strength profile.")
                    } else {
                        NavigationLink(destination: StrengthScoresView()) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(Int(overall)) / 1000")
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                    Text(StrengthScoreCalculator.levelName(for: overall))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !weeklyVolume.isEmpty {
                    ChartCard(title: "Weekly Volume", subtitle: "Total kg lifted per week") {
                        Chart(weeklyVolume, id: \.week) { point in
                            BarMark(x: .value("Week", point.week, unit: .weekOfYear),
                                    y: .value("Volume", point.volume))
                                .foregroundStyle(Color.accentColor.gradient)
                        }
                    }
                }

                if !templates.isEmpty {
                    DashboardCard(title: "Templates", systemImage: "square.on.square") {
                        VStack(spacing: 10) {
                            ForEach(templates) { template in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.title).font(.subheadline.weight(.semibold))
                                        Text("\(template.exerciseList.count) exercises")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Start") { startFromTemplate(template) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                DashboardCard(title: "History", systemImage: "clock.arrow.circlepath") {
                    if history.isEmpty {
                        EmptyStateView(systemImage: "dumbbell", title: "Add your first workout", message: "Generate a plan or start a blank workout when you train.")
                    } else {
                        VStack(spacing: 10) {
                            ForEach(history.prefix(12)) { workout in
                                NavigationLink {
                                    if workout.completed {
                                        CompletedWorkoutDetailView(workout: workout)
                                    } else {
                                        WorkoutLogView(workout: workout)
                                    }
                                } label: {
                                    WorkoutRowView(workout: workout)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { repeatWorkout(workout) } label: {
                                        Label("Repeat Workout", systemImage: "arrow.counterclockwise")
                                    }
                                    Button { saveAsTemplate(workout) } label: {
                                        Label("Save as Template", systemImage: "square.on.square")
                                    }
                                    Button(role: .destructive) { context.delete(workout) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .brandScreenBackground()
        .navigationTitle("Training")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: ExercisePresetsView()) {
                    Image(systemName: "list.bullet.clipboard")
                }
            }
        }
        .sheet(isPresented: $showGenerator) { WorkoutGeneratorView() }
        .sheet(isPresented: $showScheduleGenerator) { WorkoutScheduleGeneratorView() }
        .sheet(item: $activeWorkout) { workout in
            NavigationStack { WorkoutLogView(workout: workout, isDraft: activeWorkoutIsDraft) }
        }
    }

    private func upcomingSessionCard(_ session: WorkoutScheduleSession, date: Date) -> some View {
        DashboardCard(title: "Next Scheduled Workout", systemImage: "calendar.badge.clock") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                    Text("\(date.isToday ? "Today" : Weekday.label(session.weekday)) · \(date.formatted(date: .omitted, time: .shortened)) · ~\(session.estimatedDurationMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(date.isToday ? "Start" : "Preview") { startSession(session) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var activeSchedulesCard: some View {
        DashboardCard(title: "Active Schedules", systemImage: "calendar.day.timeline.left") {
            VStack(spacing: 10) {
                ForEach(activeSchedules, id: \.persistentModelID) { schedule in
                    NavigationLink(destination: WorkoutScheduleDetailView(schedule: schedule)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(schedule.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(schedule.sessionList.map { Weekday.shortLabel($0.weekday) }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if schedule.syncToCalendar && !schedule.calendarEventIds.isEmpty {
                                Image(systemName: "calendar.badge.checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private func startSession(_ session: WorkoutScheduleSession) {
        activeWorkoutIsDraft = false
        activeWorkout = WorkoutScheduleGeneratorService.workout(
            for: session, existingWorkouts: history, context: context)
    }

    private func createBlankWorkout() {
        // Not inserted here: only Save/Finish in WorkoutLogView commits a
        // blank workout to the store, so backing out via Cancel never
        // leaves a stray entry in history.
        activeWorkoutIsDraft = true
        activeWorkout = Workout(date: .now, title: "Workout", type: .custom)
    }

    private func startFromTemplate(_ template: Workout) {
        context.insert(copy(of: template, title: template.title.replacingOccurrences(of: " (Template)", with: ""), asTemplate: false))
    }

    private func repeatWorkout(_ workout: Workout) {
        context.insert(copy(of: workout, title: workout.title, asTemplate: false))
    }

    private func saveAsTemplate(_ workout: Workout) {
        context.insert(copy(of: workout, title: workout.title + " (Template)", asTemplate: true))
    }

    /// Deep copy with sets reset to planned (not completed) state.
    private func copy(of source: Workout, title: String, asTemplate: Bool) -> Workout {
        let workout = Workout(date: .now, title: title, type: source.type,
                              duration: source.duration, notes: source.notes, isTemplate: asTemplate)
        for exercise in source.exerciseList {
            let newExercise = Exercise(name: exercise.name, muscleGroups: exercise.muscleGroups,
                                       movementPattern: exercise.movementPattern, equipment: exercise.equipment,
                                       order: exercise.order, restSeconds: exercise.restSeconds,
                                       targetRPE: exercise.targetRPE, notes: exercise.notes)
            for set in exercise.setList {
                newExercise.sets?.append(WorkoutSet(order: set.order, reps: set.reps, weight: set.weight,
                                                    duration: set.duration, distance: set.distance))
            }
            workout.exercises?.append(newExercise)
        }
        return workout
    }
}
