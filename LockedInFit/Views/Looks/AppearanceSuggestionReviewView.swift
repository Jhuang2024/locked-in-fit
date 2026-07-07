import SwiftUI
import SwiftData

/// Review pending appearance suggestions and route approvals: checklist,
/// Google Calendar, workout schedule, or save-only. Nothing activates without
/// an explicit approve.
struct AppearanceSuggestionReviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AppearanceSuggestion.createdAt, order: .reverse) private var suggestions: [AppearanceSuggestion]

    @State private var editingSuggestion: AppearanceSuggestion?
    @State private var schedulingSuggestion: AppearanceSuggestion?
    @State private var checklistSuggestion: AppearanceSuggestion?
    @State private var showScheduleGenerator = false

    private var pending: [AppearanceSuggestion] {
        suggestions.filter { $0.status == .pending }.sorted { $0.priority < $1.priority }
    }
    private var active: [AppearanceSuggestion] {
        suggestions.filter { $0.status == .approved }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if pending.isEmpty && active.isEmpty {
                    DashboardCard(title: "Suggestions", systemImage: "lightbulb") {
                        EmptyStateView(systemImage: "lightbulb",
                                       title: "No suggestions yet",
                                       message: "Complete a face or body check-in to generate specific, reviewable suggestions.")
                    }
                }

                if !pending.isEmpty {
                    SectionLabel(text: "Pending Review (\(pending.count))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(pending, id: \.persistentModelID) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            onApprove: { approve(suggestion) },
                            onEdit: { editingSuggestion = suggestion },
                            onReject: { withAnimation(.snappy) { suggestion.status = .rejected } },
                            onSaveForLater: { withAnimation(.snappy) {
                                suggestion.destination = .saveOnly
                                suggestion.status = .approved
                            } })
                    }
                }

                if !active.isEmpty {
                    SectionLabel(text: "Active (\(active.count))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(active, id: \.persistentModelID) { suggestion in
                        activeRow(suggestion)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSuggestion) { suggestion in
            SuggestionEditView(suggestion: suggestion)
        }
        .sheet(item: $schedulingSuggestion) { suggestion in
            SuggestionCalendarSheet(suggestion: suggestion)
        }
        .sheet(item: $checklistSuggestion) { suggestion in
            SuggestionChecklistSheet(suggestion: suggestion)
        }
        .sheet(isPresented: $showScheduleGenerator) {
            WorkoutScheduleGeneratorView()
        }
    }

    private func approve(_ suggestion: AppearanceSuggestion) {
        switch suggestion.destination {
        case .checklist:
            checklistSuggestion = suggestion
        case .calendar:
            schedulingSuggestion = suggestion
        case .workoutSchedule:
            suggestion.status = .approved
            showScheduleGenerator = true
        case .saveOnly:
            withAnimation(.snappy) { suggestion.status = .approved }
        }
    }

    private func activeRow(_ suggestion: AppearanceSuggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.category.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.medium))
                Label(suggestion.destination.label, systemImage: suggestion.destination.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(.snappy) { suggestion.status = .completed }
            } label: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .cardBackground()
        .contextMenu {
            Button(role: .destructive) { remove(suggestion) } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func remove(_ suggestion: AppearanceSuggestion) {
        // Clean up whatever the approval created.
        if let eventId = suggestion.calendarEventId, GoogleCalendarService.shared.isConnected {
            Task { try? await GoogleCalendarService.shared.deleteEvent(id: eventId) }
        }
        if let itemId = suggestion.checklistItemId {
            let descriptor = FetchDescriptor<DailyChecklistItem>(predicate: #Predicate { $0.uuid == itemId })
            if let item = try? context.fetch(descriptor).first {
                context.delete(item)
            }
        }
        context.delete(suggestion)
    }
}

// MARK: - SuggestionCard

private struct SuggestionCard: View {
    @Bindable var suggestion: AppearanceSuggestion
    var onApprove: () -> Void
    var onEdit: () -> Void
    var onReject: () -> Void
    var onSaveForLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: suggestion.category.systemImage)
                    .foregroundStyle(.tint)
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(suggestion.durationType.label)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Text(suggestion.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(suggestion.expectedImpact)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Destination", selection: Binding(
                get: { suggestion.destination },
                set: { suggestion.destination = $0 })) {
                ForEach(AppearanceSuggestionDestination.allCases) { destination in
                    Label(destination.label, systemImage: destination.systemImage).tag(destination)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)

            HStack(spacing: 8) {
                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button(action: onEdit) {
                    Text("Edit")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(action: onSaveForLater) {
                    Text("Later")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(role: .destructive, action: onReject) {
                    Text("Reject")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(CardMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

// MARK: - Edit sheet

private struct SuggestionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var suggestion: AppearanceSuggestion

    var body: some View {
        NavigationStack {
            Form {
                Section("Suggestion") {
                    TextField("Title", text: $suggestion.title)
                    TextField("Explanation", text: $suggestion.explanation, axis: .vertical)
                    TextField("Expected impact", text: $suggestion.expectedImpact, axis: .vertical)
                }
                Section("Routing") {
                    Picker("Category", selection: Binding(get: { suggestion.category }, set: { suggestion.category = $0 })) {
                        ForEach(AppearanceSuggestionCategory.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Destination", selection: Binding(get: { suggestion.destination }, set: { suggestion.destination = $0 })) {
                        ForEach(AppearanceSuggestionDestination.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Duration", selection: Binding(get: { suggestion.durationType }, set: { suggestion.durationType = $0 })) {
                        ForEach(SuggestionDurationType.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle("Edit Suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Checklist approval sheet

/// Approve → checklist: pick the recurrence, then the item lands on Today.
private struct SuggestionChecklistSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let suggestion: AppearanceSuggestion

    @State private var recurrence: ChecklistRecurrence = .daily
    @State private var customWeekdays: Set<Int> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(suggestion.title)
                        .font(.subheadline.weight(.semibold))
                    Text(suggestion.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Repeat") {
                    Picker("Recurrence", selection: $recurrence) {
                        ForEach(ChecklistRecurrence.allCases) { Text($0.label).tag($0) }
                    }
                    if recurrence == .custom {
                        ForEach(Weekday.all, id: \.self) { day in
                            Toggle(Weekday.label(day), isOn: Binding(
                                get: { customWeekdays.contains(day) },
                                set: { on in if on { customWeekdays.insert(day) } else { customWeekdays.remove(day) } }))
                        }
                    }
                }
            }
            .navigationTitle("Add to Checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        DailyChecklistService.createItem(
                            from: suggestion,
                            recurrence: recurrence,
                            customWeekdays: Array(customWeekdays).sorted(),
                            context: context)
                        suggestion.status = .approved
                        suggestion.destination = .checklist
                        dismiss()
                    }
                    .disabled(recurrence == .custom && customWeekdays.isEmpty)
                }
            }
            .onAppear {
                recurrence = suggestion.durationType == .shortTerm ? .daily : .weekdays
            }
        }
    }
}

// MARK: - Calendar approval sheet

/// Approve → Google Calendar: connect if needed, then pick date/time/recurrence/
/// reminder and create the event.
private struct SuggestionCalendarSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let suggestion: AppearanceSuggestion

    @State private var startDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var recurrence: CalendarRecurrenceOption = .none
    @State private var reminderMinutes = 30
    @State private var creating = false
    @State private var errorMessage: String?

    private var service: GoogleCalendarService { .shared }

    enum CalendarRecurrenceOption: String, CaseIterable, Identifiable {
        case none, daily, weekly
        case every4Weeks = "every_4_weeks"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "One-time"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .every4Weeks: return "Every 4 weeks"
            }
        }
        var rrule: String? {
            switch self {
            case .none: return nil
            case .daily: return "FREQ=DAILY"
            case .weekly: return "FREQ=WEEKLY"
            case .every4Weeks: return "FREQ=WEEKLY;INTERVAL=4"
            }
        }
    }

    /// isConnected comes from the Keychain, so this also reads the observable
    /// isAuthenticating flag — its transition re-evaluates body right after the
    /// child connect flow finishes, flipping straight to the scheduling form.
    private var showSchedulingForm: Bool {
        _ = service.isAuthenticating
        return service.isConnected
    }

    var body: some View {
        NavigationStack {
            Group {
                if showSchedulingForm {
                    schedulingForm
                } else {
                    GoogleCalendarConnectView()
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var schedulingForm: some View {
        Form {
            Section {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                Text(suggestion.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("When") {
                DatePicker("Date & time", selection: $startDate)
                Picker("Repeat", selection: $recurrence) {
                    ForEach(CalendarRecurrenceOption.allCases) { Text($0.label).tag($0) }
                }
                Picker("Reminder", selection: $reminderMinutes) {
                    Text("At time").tag(0)
                    Text("10 min before").tag(10)
                    Text("30 min before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("1 day before").tag(1440)
                }
            }
            Section {
                Button {
                    Task { await createEvent() }
                } label: {
                    if creating {
                        HStack { ProgressView(); Text("Creating event…") }
                    } else {
                        Label("Create Calendar Event", systemImage: "calendar.badge.plus")
                    }
                }
                .disabled(creating)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                if let email = service.connectedEmail {
                    Text("Creates \"LockedInFit: \(suggestion.title)\" on \(email)'s primary calendar.")
                }
            }
        }
    }

    private func createEvent() async {
        creating = true
        defer { creating = false }
        errorMessage = nil
        // Update instead of duplicate if this suggestion already made an event.
        let payload = CalendarEventPayload.forSuggestion(
            suggestion, start: startDate,
            recurrenceRule: recurrence.rrule,
            reminderMinutes: reminderMinutes == 0 ? nil : reminderMinutes)
        do {
            if let existingId = suggestion.calendarEventId {
                try await service.updateEvent(id: existingId, payload: payload)
            } else {
                let eventId = try await service.createEvent(payload)
                suggestion.calendarEventId = eventId
            }
            suggestion.status = .approved
            suggestion.destination = .calendar
            suggestion.suggestedDate = startDate
            suggestion.recurrenceRule = recurrence.rrule
            updateConnectionSyncDate()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateConnectionSyncDate() {
        let descriptor = FetchDescriptor<CalendarConnectionState>()
        if let state = try? context.fetch(descriptor).first {
            state.lastSyncDate = .now
        }
    }
}
