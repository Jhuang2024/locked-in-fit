import SwiftUI
import SwiftData

/// Hub for sleep tracking: latest score, log entry, recent history, and the
/// entry point into Sleep Trends. Mirrors LooksDashboardView's structure.
struct SleepDashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SleepLog.date, order: .reverse) private var logs: [SleepLog]

    @State private var showLogSheet = false

    private var latest: SleepLog? { logs.first }
    private var streak: Int { SleepScoringService.streak(history: logs) }
    private var avgDurationHours: Double? {
        let recent = logs.prefix(7)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.durationHours } / Double(recent.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                scoreCard
                statsCard
                actionButtons
                if logs.isEmpty {
                    explainerCard
                } else {
                    recentLogsCard
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sleep")
        .sheet(isPresented: $showLogSheet) { NavigationStack { SleepLogEntryView() } }
    }

    private var scoreCard: some View {
        DashboardCard(title: "Sleep Score", systemImage: "bed.double.fill") {
            HStack(spacing: 16) {
                scoreRing
                VStack(alignment: .leading, spacing: 4) {
                    if let latest {
                        Label(Formatters.mediumDate(latest.date), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label("\(Formatters.trimmed(latest.durationHours))h · \(latest.wakeUps) wake-up\(latest.wakeUps == 1 ? "" : "s")", systemImage: "moon.zzz")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Log your bedtime and wake time to start tracking your sleep score.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if latest != nil {
                Text("Tap the score for its breakdown.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var scoreRing: some View {
        let ring = ScoreRingView(label: "Sleep", score: latest?.totalScore ?? 0, maxScore: 100,
                                  color: latest == nil ? .gray : .indigo)
        if let latest {
            NavigationLink(destination: SleepLogDetailView(log: latest)) { ring }
                .buttonStyle(.pressable)
        } else {
            ring
        }
    }

    private var statsCard: some View {
        DashboardCard(title: "Status", systemImage: "chart.bar") {
            HStack {
                StatChip(label: "Streak", value: streak > 0 ? "\(streak)d" : "N/A")
                StatChip(label: "Avg 7-night", value: avgDurationHours.map { "\(Formatters.trimmed($0))h" } ?? "N/A")
                StatChip(label: "Logs", value: "\(logs.count)")
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button { showLogSheet = true } label: {
                Label("Log Sleep", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            NavigationLink(destination: SleepTrendsView()) {
                Label("Sleep Trends", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
    }

    private var explainerCard: some View {
        DashboardCard(title: "How it works", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                explainerRow(icon: "bed.double", text: "Log your bedtime, wake time, and wake-ups each morning.")
                explainerRow(icon: "chart.bar", text: "Your sleep score comes from duration, consistency with your own history, interruptions, and bedtime timing, never a random or guessed number.")
                explainerRow(icon: "lightbulb", text: "Each log gets a full breakdown and a few specific suggestions for the next night.")
            }
        }
    }

    private func explainerRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recentLogsCard: some View {
        DashboardCard(title: "Recent Logs", systemImage: "clock.arrow.circlepath") {
            VStack(spacing: 10) {
                ForEach(logs.prefix(8), id: \.persistentModelID) { log in
                    NavigationLink(destination: SleepLogDetailView(log: log)) {
                        logRow(log)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        Button(role: .destructive) { context.delete(log) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func logRow(_ log: SleepLog) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.mediumDate(log.date))
                    .font(.subheadline.weight(.semibold))
                Text("\(Formatters.trimmed(log.durationHours))h · \(log.wakeUps) wake-up\(log.wakeUps == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(log.totalScore))")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Text("/100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Sleep log detail

struct SleepLogDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let log: SleepLog

    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DashboardCard(title: "Sleep Score", systemImage: "bed.double.fill") {
                    HStack(spacing: 16) {
                        ScoreRingView(label: Formatters.mediumDate(log.date), score: log.totalScore, maxScore: 100, color: .indigo)
                        VStack(alignment: .leading, spacing: 4) {
                            Label("\(Formatters.trimmed(log.durationHours))h asleep", systemImage: "moon.zzz")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label("\(log.wakeUps) wake-up\(log.wakeUps == 1 ? "" : "s")", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                DashboardCard(title: "Sleep Details", systemImage: "clock") {
                    HStack {
                        StatChip(label: "Bedtime", value: log.sleepStart.formatted(date: .omitted, time: .shortened))
                        StatChip(label: "Wake time", value: log.sleepEnd.formatted(date: .omitted, time: .shortened))
                        StatChip(label: "Duration", value: "\(Formatters.trimmed(log.durationHours))h")
                        StatChip(label: "Wake-ups", value: "\(log.wakeUps)")
                    }
                }

                DashboardCard(title: "Score Breakdown", systemImage: "list.bullet.rectangle") {
                    VStack(spacing: 8) {
                        breakdownRow("Duration", log.durationScore, 40)
                        breakdownRow("Consistency", log.consistencyScore, 25)
                        breakdownRow("Interruptions", log.interruptionScore, 20)
                        breakdownRow("Timing", log.timingScore, 15)
                    }
                }

                if !log.explanations.isEmpty {
                    DashboardCard(title: "Why This Score?", systemImage: "questionmark.circle") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(log.explanations, id: \.self) { line in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").font(.caption).foregroundStyle(.tertiary)
                                    Text(line).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !log.suggestions.isEmpty {
                    DashboardCard(title: "Suggestions", systemImage: "lightbulb") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(log.suggestions, id: \.self) { line in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").font(.caption).foregroundStyle(.tertiary)
                                    Text(line).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !log.notes.isEmpty {
                    DashboardCard(title: "Notes", systemImage: "note.text") {
                        Text(log.notes)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sleep Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
        }
        .confirmationDialog("Delete this sleep log?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(log)
                dismiss()
            }
        }
    }

    private func breakdownRow(_ label: String, _ value: Double, _ max: Double) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(max))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(value, max), total: max)
                .tint(value / max >= 0.7 ? .green : value / max >= 0.4 ? .orange : .red)
        }
    }
}

// MARK: - Sleep log entry

struct SleepLogEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SleepLog.date, order: .reverse) private var logs: [SleepLog]

    @State private var sleepStart: Date = Calendar.current.date(
        bySettingHour: 23, minute: 0, second: 0, of: Date().daysAgo(1)) ?? Date().daysAgo(1)
    @State private var sleepEnd: Date = Calendar.current.date(
        bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var wakeUps: Int = 0
    @State private var notes: String = ""

    private var durationHours: Double {
        SleepScoringService.durationHours(sleepStart: sleepStart, sleepEnd: sleepEnd)
    }

    var body: some View {
        Form {
            Section("Bedtime & Wake Time") {
                DatePicker("Went to sleep", selection: $sleepStart, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Woke up", selection: $sleepEnd, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    Text("Duration")
                    Spacer()
                    Text("\(Formatters.trimmed(durationHours))h")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Interruptions") {
                Stepper("Woke up \(wakeUps) time\(wakeUps == 1 ? "" : "s")", value: $wakeUps, in: 0...10)
            }
            Section("Notes") {
                TextField("Optional: how you felt, caffeine, stress…", text: $notes, axis: .vertical)
            }
        }
        .navigationTitle("Log Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .keyboardDoneToolbar()
    }

    private func save() {
        let hours = durationHours
        let result = SleepScoringService.score(sleepStart: sleepStart, sleepEnd: sleepEnd, wakeUps: wakeUps,
                                               history: logs, date: sleepStart)
        let log = SleepLog(date: sleepStart.startOfDay, sleepStart: sleepStart, sleepEnd: sleepEnd,
                           wakeUps: wakeUps, durationHours: hours, totalScore: result.total, notes: notes)
        log.durationScore = result.duration
        log.consistencyScore = result.consistency
        log.interruptionScore = result.interruptions
        log.timingScore = result.timing
        log.explanations = result.explanations
        log.suggestions = result.suggestions
        context.insert(log)
        dismiss()
    }
}
