import SwiftUI
import SwiftData

/// Generates a full weekly training schedule (vs. the existing one-off
/// generator), previews it, and saves with optional reminders + Calendar sync.
struct WorkoutScheduleGeneratorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    @State private var goal: WorkoutScheduleGoal = .muscleGain
    @State private var experience: WorkoutExperienceLevel = .intermediate
    @State private var daysPerWeek = 3
    @State private var sessionLength = 60
    @State private var equipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable, .bodyweight]
    @State private var targetMuscles: Set<MuscleGroup> = []
    @State private var preferredWeekdays: Set<Int> = []
    @State private var limitations = ""
    @State private var startDate = Date()
    @State private var sessionTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now) ?? .now
    @State private var syncToCalendar = false
    @State private var preview: WorkoutSchedule?

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    WorkoutSchedulePreviewSection(schedule: preview, onSave: { save(preview) })
                }

                Section("Goal") {
                    Picker("Goal", selection: $goal) {
                        ForEach(WorkoutScheduleGoal.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Experience", selection: $experience) {
                        ForEach(WorkoutExperienceLevel.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Structure") {
                    Stepper("Days per week: \(daysPerWeek)", value: $daysPerWeek, in: 2...6)
                    Picker("Session length", selection: $sessionLength) {
                        ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    DatePicker("Session time", selection: $sessionTime, displayedComponents: .hourAndMinute)
                }

                Section {
                    ForEach(Weekday.all, id: \.self) { day in
                        Toggle(Weekday.label(day), isOn: Binding(
                            get: { preferredWeekdays.contains(day) },
                            set: { on in if on { preferredWeekdays.insert(day) } else { preferredWeekdays.remove(day) } }))
                    }
                } header: {
                    Text("Preferred days (optional)")
                } footer: {
                    Text("Pick up to \(daysPerWeek). Unpicked slots get spaced automatically with rest days between sessions.")
                }

                Section("Equipment available") {
                    ForEach(Equipment.allCases) { item in
                        Toggle(item.label, isOn: Binding(
                            get: { equipment.contains(item) },
                            set: { on in if on { equipment.insert(item) } else { equipment.remove(item) } }))
                    }
                }

                Section("Focus muscles (optional)") {
                    ForEach(MuscleGroup.allCases) { muscle in
                        Toggle(muscle.label, isOn: Binding(
                            get: { targetMuscles.contains(muscle) },
                            set: { on in if on { targetMuscles.insert(muscle) } else { targetMuscles.remove(muscle) } }))
                    }
                }

                Section("Limitations / injuries (optional)") {
                    TextField("e.g. no overhead pressing, left knee", text: $limitations, axis: .vertical)
                }

                Section {
                    Toggle("Sync to Google Calendar", isOn: $syncToCalendar)
                } footer: {
                    if syncToCalendar && !GoogleCalendarService.shared.isConnected {
                        Text("Google Calendar isn't connected yet — you'll be able to connect when saving, or the schedule saves with local reminders only.")
                    } else {
                        Text("Optional. Local workout reminders work with or without Calendar sync.")
                    }
                }
            }
            .navigationTitle("Generate Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(preview == nil ? "Generate" : "Regenerate") { generate() }
                        .disabled(equipment.isEmpty)
                }
            }
        }
    }

    private func generate() {
        let calendar = Calendar.current
        let request = WorkoutScheduleGeneratorService.ScheduleRequest(
            goal: goal,
            experience: experience,
            daysPerWeek: daysPerWeek,
            sessionLengthMinutes: sessionLength,
            equipment: equipment,
            preferredWeekdays: Array(preferredWeekdays).sorted(),
            targetMuscles: targetMuscles,
            limitations: limitations,
            startDate: startDate,
            sessionHour: calendar.component(.hour, from: sessionTime),
            sessionMinute: calendar.component(.minute, from: sessionTime),
            syncToCalendar: syncToCalendar)
        withAnimation(.snappy) {
            preview = WorkoutScheduleGeneratorService.generate(request: request)
        }
    }

    private func save(_ schedule: WorkoutSchedule) {
        context.insert(schedule)

        // Local reminders (independent of Calendar).
        if let settings, settings.workoutRemindersEnabled {
            Task {
                if await NotificationService.ensureAuthorization() {
                    await NotificationService.refreshWorkoutReminders(
                        schedule: schedule,
                        enabled: true,
                        offsetMinutes: settings.defaultWorkoutReminderMinutes)
                }
            }
        }

        // Optional Calendar sync — failures never block the save.
        if schedule.syncToCalendar && GoogleCalendarService.shared.isConnected {
            let reminderMinutes = settings?.defaultWorkoutReminderMinutes ?? 60
            Task { await syncScheduleToCalendar(schedule, reminderMinutes: reminderMinutes) }
        }
        dismiss()
    }

    private func syncScheduleToCalendar(_ schedule: WorkoutSchedule, reminderMinutes: Int) async {
        for session in schedule.sessionList {
            guard session.calendarEventId == nil, // never duplicate
                  let payload = CalendarEventPayload.forSession(session, schedule: schedule, reminderMinutes: reminderMinutes) else { continue }
            if let eventId = try? await GoogleCalendarService.shared.createEvent(payload) {
                session.calendarEventId = eventId
                schedule.calendarEventIds.append(eventId)
            }
        }
    }
}

// MARK: - Preview section

/// Inline preview inside the generator form; also reused by the schedule detail.
struct WorkoutSchedulePreviewSection: View {
    let schedule: WorkoutSchedule
    var onSave: (() -> Void)?

    var body: some View {
        Section {
            ForEach(schedule.sessionList, id: \.persistentModelID) { session in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Weekday.label(session.weekday))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                        Spacer()
                        Text("~\(session.estimatedDurationMinutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                    ForEach(session.plannedExercises) { exercise in
                        HStack {
                            Text(exercise.name)
                                .font(.caption)
                            Spacer()
                            Text(exercise.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if let onSave {
                Button {
                    onSave()
                } label: {
                    Label("Save Schedule", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("Preview: \(schedule.title)")
        } footer: {
            Text(schedule.progressionNote)
        }
    }
}

// MARK: - Schedule detail

/// Full detail for a saved schedule: sessions, per-session reminder toggles,
/// calendar sync state, and deletion (with event cleanup).
struct WorkoutScheduleDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    @Bindable var schedule: WorkoutSchedule
    @State private var confirmDelete = false
    @State private var syncMessage: String?
    @State private var syncing = false

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        Form {
            Section {
                LabeledContent("Goal", value: schedule.goal.label)
                LabeledContent("Experience", value: schedule.experience.label)
                LabeledContent("Days/week", value: "\(schedule.daysPerWeek)")
                LabeledContent("Session length", value: "\(schedule.sessionLengthMinutes) min")
                LabeledContent("Started", value: Formatters.mediumDate(schedule.startDate))
            }

            ForEach(schedule.sessionList, id: \.persistentModelID) { session in
                sessionSection(session)
            }

            Section {
                Text(schedule.progressionNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Progression")
            }

            Section("Google Calendar") {
                if schedule.calendarEventIds.isEmpty {
                    Button {
                        Task { await syncNow() }
                    } label: {
                        if syncing {
                            HStack { ProgressView(); Text("Syncing…") }
                        } else {
                            Label("Sync Sessions to Calendar", systemImage: "calendar.badge.plus")
                        }
                    }
                    .disabled(syncing || !GoogleCalendarService.shared.isConnected)
                    if !GoogleCalendarService.shared.isConnected {
                        Text("Connect Google Calendar in Settings → Looks & Calendar first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("Synced events", value: "\(schedule.calendarEventIds.count)")
                }
                if let syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("End Schedule", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(schedule.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("End this schedule? Linked reminders and calendar events are removed.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("End Schedule", role: .destructive) { deleteSchedule() }
        }
    }

    private func sessionSection(_ session: WorkoutScheduleSession) -> some View {
        Section {
            ForEach(session.plannedExercises) { exercise in
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.medium))
                    Text(exercise.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !exercise.note.isEmpty {
                        Text(exercise.note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Toggle("Reminder", isOn: Binding(
                get: { session.reminderEnabled },
                set: { newValue in
                    session.reminderEnabled = newValue
                    refreshReminders()
                }))
        } header: {
            Text("\(Weekday.label(session.weekday)) · \(session.title)")
        }
    }

    private func refreshReminders() {
        guard let settings else { return }
        Task {
            await NotificationService.refreshWorkoutReminders(
                schedule: schedule,
                enabled: settings.workoutRemindersEnabled,
                offsetMinutes: settings.defaultWorkoutReminderMinutes)
        }
    }

    private func syncNow() async {
        syncing = true
        defer { syncing = false }
        let reminderMinutes = settings?.defaultWorkoutReminderMinutes ?? 60
        var created = 0
        for session in schedule.sessionList {
            guard session.calendarEventId == nil,
                  let payload = CalendarEventPayload.forSession(session, schedule: schedule, reminderMinutes: reminderMinutes) else { continue }
            do {
                let eventId = try await GoogleCalendarService.shared.createEvent(payload)
                session.calendarEventId = eventId
                schedule.calendarEventIds.append(eventId)
                created += 1
            } catch {
                syncMessage = error.localizedDescription
                return
            }
        }
        schedule.syncToCalendar = true
        syncMessage = created > 0 ? "Created \(created) recurring events." : "Sessions were already synced."
    }

    private func deleteSchedule() {
        let uuid = schedule.uuid
        let eventIds = schedule.calendarEventIds
        Task {
            await NotificationService.cancelWorkoutReminders(scheduleUUID: uuid)
            if GoogleCalendarService.shared.isConnected {
                for id in eventIds {
                    try? await GoogleCalendarService.shared.deleteEvent(id: id)
                }
            }
        }
        context.delete(schedule)
        dismiss()
    }
}
