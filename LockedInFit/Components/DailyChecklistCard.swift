import SwiftUI
import SwiftData

/// The Today checklist: due persisted items, plus system rows for today's face
/// photo and any scheduled workout. Completed items stay visible but collapse
/// into a subtle "done" group.
struct DailyChecklistCard: View {
    @Environment(\.modelContext) private var context

    let items: [DailyChecklistItem]
    /// Whether a face check-in already exists today.
    let faceCheckedInToday: Bool
    /// Sessions from active schedules that fall on today.
    let sessionsDueToday: [WorkoutScheduleSession]
    /// Completed workouts (to mark scheduled sessions done).
    let completedWorkouts: [Workout]
    var onStartSession: (WorkoutScheduleSession) -> Void

    @State private var showAddItem = false
    @State private var completionTick = 0

    private var dueItems: [DailyChecklistItem] { DailyChecklistService.dueItems(items) }
    private var openItems: [DailyChecklistItem] { dueItems.filter { !DailyChecklistService.isCompleted($0) } }
    private var doneItems: [DailyChecklistItem] { dueItems.filter { DailyChecklistService.isCompleted($0) } }

    private var openSessions: [WorkoutScheduleSession] {
        sessionsDueToday.filter { !WorkoutScheduleGeneratorService.isCompletedToday(session: $0, workouts: completedWorkouts) }
    }
    private var doneSessions: [WorkoutScheduleSession] {
        sessionsDueToday.filter { WorkoutScheduleGeneratorService.isCompletedToday(session: $0, workouts: completedWorkouts) }
    }

    private var doneCount: Int {
        doneItems.count + doneSessions.count + (faceCheckedInToday ? 1 : 0)
    }
    private var totalCount: Int {
        dueItems.count + sessionsDueToday.count + 1 // +1 = face photo system task
    }

    var body: some View {
        DashboardCard(title: "Today's Checklist", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 10) {
                if totalCount > 0 {
                    ProgressView(value: Double(doneCount), total: Double(max(1, totalCount)))
                        .tint(doneCount == totalCount ? .green : .accentColor)
                }

                // Face photo system task.
                if !faceCheckedInToday {
                    NavigationLink(destination: FaceCheckInView()) {
                        systemRow(title: "Take today's face photo",
                                  subtitle: "Daily check-in",
                                  systemImage: "face.smiling",
                                  done: false)
                    }
                    .buttonStyle(.pressable)
                }

                // Scheduled workouts due today.
                ForEach(openSessions, id: \.persistentModelID) { session in
                    Button { onStartSession(session) } label: {
                        systemRow(title: session.title,
                                  subtitle: "Scheduled workout · ~\(session.estimatedDurationMinutes) min",
                                  systemImage: "dumbbell",
                                  done: false)
                    }
                    .buttonStyle(.pressable)
                }

                // Open persisted items.
                ForEach(openItems, id: \.persistentModelID) { item in
                    ChecklistRowView(item: item) { toggle(item) }
                }

                if openItems.isEmpty && openSessions.isEmpty && faceCheckedInToday {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("All done for today.")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.vertical, 2)
                }

                // Completed group: visible but subtle.
                if doneCount > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        if faceCheckedInToday {
                            systemRow(title: "Face photo taken", subtitle: nil, systemImage: "face.smiling", done: true)
                        }
                        ForEach(doneSessions, id: \.persistentModelID) { session in
                            systemRow(title: session.title, subtitle: nil, systemImage: "dumbbell", done: true)
                        }
                        ForEach(doneItems, id: \.persistentModelID) { item in
                            ChecklistRowView(item: item) { toggle(item) }
                        }
                    }
                    .padding(.top, 2)
                }

                Button { showAddItem = true } label: {
                    Label("Add item", systemImage: "plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
        }
        .sheet(isPresented: $showAddItem) { ChecklistItemEditView(item: nil) }
        .sensoryFeedback(.success, trigger: completionTick)
    }

    private func toggle(_ item: DailyChecklistItem) {
        withAnimation(.snappy) {
            DailyChecklistService.toggle(item)
        }
        completionTick += 1
    }

    private func systemRow(title: String, subtitle: String?, systemImage: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? .green : .secondary)
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(done ? .regular : .medium))
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done, color: .secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !done {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - ChecklistRowView

struct ChecklistRowView: View {
    @Environment(\.modelContext) private var context
    let item: DailyChecklistItem
    var onToggle: () -> Void

    @State private var showEdit = false

    private var done: Bool { DailyChecklistService.isCompleted(item) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? .green : .secondary)
            Image(systemName: item.category.systemImage)
                .font(.caption)
                .foregroundStyle(.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(done ? .regular : .medium))
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done, color: .secondary)
                if item.recurrence != .none {
                    Text(item.recurrence.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .contextMenu {
            Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { deleteItem() } label: { Label("Delete", systemImage: "trash") }
        }
        .sheet(isPresented: $showEdit) { ChecklistItemEditView(item: item) }
    }

    private func deleteItem() {
        // Clean up a linked calendar event so orphans don't pile up in Google Calendar.
        if let eventId = item.calendarEventId, GoogleCalendarService.shared.isConnected {
            Task { try? await GoogleCalendarService.shared.deleteEvent(id: eventId) }
        }
        context.delete(item)
    }
}

// MARK: - ChecklistItemEditView

/// Quick add/edit for a checklist item. Suggestion-generated items are the
/// main path; this covers manual tweaks.
struct ChecklistItemEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: DailyChecklistItem?

    @State private var title = ""
    @State private var details = ""
    @State private var category: ChecklistCategory = .manual
    @State private var recurrence: ChecklistRecurrence = .daily
    @State private var customWeekdays: Set<Int> = []
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Details (optional)", text: $details, axis: .vertical)
                    Picker("Category", selection: $category) {
                        ForEach(ChecklistCategory.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Repeat") {
                    Picker("Recurrence", selection: $recurrence) {
                        ForEach(ChecklistRecurrence.allCases) { Text($0.label).tag($0) }
                    }
                    if recurrence == .none {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
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
            .navigationTitle(item == nil ? "New Checklist Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                                  || (recurrence == .custom && customWeekdays.isEmpty))
                }
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        guard let item else { return }
        title = item.title
        details = item.details
        category = item.category
        recurrence = item.recurrence
        customWeekdays = Set(item.customWeekdays)
        dueDate = item.dueDate
    }

    private func save() {
        if let item {
            item.title = title
            item.details = details
            item.category = category
            item.recurrence = recurrence
            item.customWeekdays = Array(customWeekdays).sorted()
            item.dueDate = dueDate
        } else {
            let newItem = DailyChecklistItem(
                title: title,
                details: details,
                category: category,
                dueDate: dueDate,
                recurrence: recurrence,
                customWeekdays: Array(customWeekdays).sorted(),
                source: .manual)
            context.insert(newItem)
        }
        dismiss()
    }
}
