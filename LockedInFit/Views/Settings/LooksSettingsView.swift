import SwiftUI
import SwiftData

/// Looks & Calendar settings: reminders, Calendar connection, privacy, and
/// full deletion of appearance data.
struct LooksSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query private var checkIns: [AppearanceCheckIn]
    @Query private var suggestions: [AppearanceSuggestion]
    @Query private var checklistItems: [DailyChecklistItem]

    @State private var confirmDelete = false
    @State private var deleteResult: String?
    @State private var notificationsDenied = false

    private var settings: UserSettings? { settingsList.first }
    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings?.faceReminderHour ?? 9
                components.minute = settings?.faceReminderMinute ?? 0
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newValue in
                settings?.faceReminderHour = Calendar.current.component(.hour, from: newValue)
                settings?.faceReminderMinute = Calendar.current.component(.minute, from: newValue)
                refreshFaceReminders()
            })
    }

    var body: some View {
        Form {
            if let settings {
                faceReminderSection(settings)
                bodyReminderSection(settings)
                workoutReminderSection(settings)
            }

            Section("Google Calendar") {
                NavigationLink(destination: GoogleCalendarConnectView()) {
                    HStack {
                        Label("Calendar Connection", systemImage: "calendar")
                        Spacer()
                        Text(GoogleCalendarService.shared.isConnected
                             ? (GoogleCalendarService.shared.connectedEmail ?? "Connected")
                             : "Not connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete All Looks Data", systemImage: "trash")
                }
                if let deleteResult {
                    Text(deleteResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Removes every appearance check-in and its photos, all suggestions, and appearance-generated checklist items. Progress photos saved to your regular timeline are kept. This cannot be undone.")
            }

            Section {
                Text("""
                Face and body photos are stored on this device only, in the app's private storage. \
                Scores are computed locally from photo quality, consistency, grooming/visibility proxies, \
                your body composition data, and comparison against your own history; they are not a \
                measure of attractiveness. If OpenRouter analysis is enabled in AI settings, check-in \
                photos are sent to your chosen model only when you run an analysis, and nothing is saved \
                until you review it.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Looks & Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { PerfLog.event("nav.looksSettings.appear") }
        .confirmationDialog("Delete all Looks data and photos?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { deleteAllLooksData() }
        }
    }

    // MARK: - Sections

    private func faceReminderSection(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Daily face reminder", isOn: Binding(
                get: { settings.faceReminderEnabled },
                set: { on in
                    settings.faceReminderEnabled = on
                    if on {
                        Task {
                            let granted = await NotificationService.ensureAuthorization()
                            notificationsDenied = !granted
                            if granted { refreshFaceReminders() } else { settings.faceReminderEnabled = false }
                        }
                    } else {
                        refreshFaceReminders()
                    }
                }))
            if settings.faceReminderEnabled {
                DatePicker("Time", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
            }
            if notificationsDenied {
                Text("Notifications are turned off for Locked In Fit in iOS Settings. Enable them there to use reminders.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Face Check-In")
        } footer: {
            Text("\"Face check-in: take today's progress photo.\" Skipped automatically on days you've already checked in.")
        }
    }

    private func bodyReminderSection(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            Picker("Body photo reminder", selection: Binding(
                get: { settings.bodyReminderFrequency },
                set: { frequency in
                    settings.bodyReminderFrequency = frequency
                    settings.bodyReminderEnabled = frequency != .off
                    Task {
                        if frequency != .off {
                            let granted = await NotificationService.ensureAuthorization()
                            notificationsDenied = !granted
                            guard granted else {
                                settings.bodyReminderFrequency = .off
                                settings.bodyReminderEnabled = false
                                return
                            }
                        }
                        await NotificationService.refreshBodyReminders(
                            frequency: settings.bodyReminderFrequency,
                            hour: settings.faceReminderHour,
                            minute: settings.faceReminderMinute)
                    }
                })) {
                ForEach(BodyReminderFrequency.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            Text("Body Check-In")
        } footer: {
            Text("Off by default. Body photos are worth taking every week or two at most; never daily.")
        }
    }

    private func workoutReminderSection(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Workout reminders", isOn: Binding(
                get: { settings.workoutRemindersEnabled },
                set: { on in
                    settings.workoutRemindersEnabled = on
                    if on {
                        Task {
                            let granted = await NotificationService.ensureAuthorization()
                            notificationsDenied = !granted
                            if !granted { settings.workoutRemindersEnabled = false }
                        }
                    }
                }))
            Picker("Remind me", selection: $settings.defaultWorkoutReminderMinutes) {
                Text("15 min before").tag(15)
                Text("30 min before").tag(30)
                Text("1 hour before").tag(60)
                Text("2 hours before").tag(120)
            }
            .disabled(!settings.workoutRemindersEnabled)
        } header: {
            Text("Workouts")
        } footer: {
            Text("Applies to sessions from generated workout schedules. Works fully offline; Google Calendar is never required.")
        }
    }

    // MARK: - Delete

    private func deleteAllLooksData() {
        let checkInCount = checkIns.count
        var photoCount = 0
        for checkIn in checkIns {
            for path in checkIn.allPhotoPaths where path != nil { photoCount += 1 }
            ImageStore.deleteAll(checkIn.allPhotoPaths)
            context.delete(checkIn)
        }
        // Belt and braces: sweep any orphaned looks photos by prefix.
        ImageStore.deleteAll(withPrefixes: ["face", "body-front", "body-side", "body-back"])

        let suggestionCount = suggestions.count
        for suggestion in suggestions {
            if let eventId = suggestion.calendarEventId, GoogleCalendarService.shared.isConnected {
                Task { try? await GoogleCalendarService.shared.deleteEvent(id: eventId) }
            }
            context.delete(suggestion)
        }
        var itemCount = 0
        for item in checklistItems where item.source == .appearanceSuggestion || item.source == .system {
            if let eventId = item.calendarEventId, GoogleCalendarService.shared.isConnected {
                Task { try? await GoogleCalendarService.shared.deleteEvent(id: eventId) }
            }
            context.delete(item)
            itemCount += 1
        }
        deleteResult = "Deleted \(checkInCount) check-ins, \(photoCount) photos, \(suggestionCount) suggestions, \(itemCount) checklist items."
    }

    private func refreshFaceReminders() {
        guard let settings else { return }
        let checkedInToday = checkIns.contains { $0.kind == .face && $0.date.isToday }
        Task {
            await NotificationService.refreshFaceReminders(
                enabled: settings.faceReminderEnabled,
                hour: settings.faceReminderHour,
                minute: settings.faceReminderMinute,
                faceCheckedInToday: checkedInToday)
        }
    }
}
