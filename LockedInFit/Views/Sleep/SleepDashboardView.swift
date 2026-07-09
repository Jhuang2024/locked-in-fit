import SwiftUI
import SwiftData

/// Hub for sleep tracking: latest score, log entry, recent history, and the
/// entry point into Sleep Trends. Mirrors LooksDashboardView's structure.
struct SleepDashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\SleepLog.date, order: .reverse), SortDescriptor(\SleepLog.createdAt, order: .reverse)])
    private var logs: [SleepLog]
    @Query(sort: \NapLog.napStart, order: .reverse) private var naps: [NapLog]

    @State private var showLogSheet = false
    @State private var showNapSheet = false

    private var latest: SleepLog? { logs.first }
    private var streak: Int { SleepScoringService.streak(history: logs) }
    /// One entry per calendar night — a read-only view, nothing is deleted
    /// from the store — so a leftover duplicate night (see
    /// SleepLogEntryView.save) can't double-count itself into the average
    /// or the Logs count. Recent Logs below intentionally still shows every
    /// individual entry, duplicates included, since that's where a genuine
    /// duplicate is visible and can be removed manually (swipe/long-press
    /// to delete) — the one place deletion should be a deliberate choice,
    /// not something this screen does on its own.
    private var distinctLogs: [SleepLog] { SleepScoringService.distinctNights(logs) }
    private var avgDurationHours: Double? {
        let recent = distinctLogs.prefix(7)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.durationHours } / Double(recent.count)
    }
    private var todayNaps: [NapLog] { naps.filter { $0.date.isToday } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                scoreCard
                statsCard
                actionButtons
                if !todayNaps.isEmpty {
                    todayNapsCard
                }
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
        .sheet(isPresented: $showNapSheet) { NavigationStack { NapLogEntryView() } }
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
                StatChip(label: "Logs", value: "\(distinctLogs.count)")
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { showLogSheet = true } label: {
                    Label("Log Sleep", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                Button { showNapSheet = true } label: {
                    Label("Log Nap", systemImage: "zzz")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.mint)
            }
            NavigationLink(destination: SleepTrendsView()) {
                Label("Sleep Trends", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
    }

    private var todayNapsCard: some View {
        DashboardCard(title: "Today's Naps", systemImage: "zzz") {
            VStack(spacing: 10) {
                ForEach(todayNaps, id: \.persistentModelID) { nap in
                    napRow(nap)
                        .contextMenu {
                            Button(role: .destructive) { deleteNap(nap) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func napRow(_ nap: NapLog) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "zzz")
                .font(.title3)
                .foregroundStyle(.mint)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(nap.napStart.formatted(date: .omitted, time: .shortened)) – \(nap.napEnd.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline.weight(.semibold))
                Text(Formatters.napDuration(nap.durationMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// Deletes a nap and, if today's overnight log already exists, recomputes
    /// its score from the remaining naps so the two stay in sync.
    private func deleteNap(_ nap: NapLog) {
        let day = nap.date
        context.delete(nap)
        if let log = logs.first(where: { $0.date == day }) {
            let remaining = naps.filter { $0.date == day && $0.uuid != nap.uuid }
            SleepScoringService.recompute(log, history: logs, naps: remaining)
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
    @Query(sort: [SortDescriptor(\SleepLog.date, order: .reverse), SortDescriptor(\SleepLog.createdAt, order: .reverse)])
    private var allLogs: [SleepLog]
    @Query(sort: \NapLog.napStart) private var allNaps: [NapLog]
    let log: SleepLog

    @State private var confirmDelete = false

    private var dayNaps: [NapLog] { allNaps.filter { $0.date == log.date } }

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
                        if !dayNaps.isEmpty {
                            napImpactRow(log.napContributionScore)
                        }
                    }
                }

                if !dayNaps.isEmpty {
                    napImpactCard
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
        .onAppear {
            // Self-heals any log whose stored nap score/explanations were
            // computed under a past scoring bug: recomputing from the
            // current naps for this day with today's logic is always safe
            // (recompute is idempotent) and needs no data migration.
            SleepScoringService.recompute(log, history: allLogs, naps: dayNaps)
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

    /// Naps can help (up to +napBonusCap) or hurt (down to napPenaltyCap)
    /// instead of climbing toward one fixed max like the other rows, so this
    /// shows how much of *that direction's* cap the nap contribution used —
    /// same "value / cap" bar as breakdownRow (identical ProgressView, same
    /// thickness), just green filling up toward the bonus cap or red filling
    /// up toward the penalty cap.
    private func napImpactRow(_ value: Double) -> some View {
        let cap = value < 0 ? abs(SleepScoringService.napPenaltyCap) : SleepScoringService.napBonusCap
        let magnitude = min(abs(value), cap)
        return VStack(spacing: 3) {
            HStack {
                Text("Naps")
                    .font(.caption.weight(.medium))
                Spacer()
                Text(value == 0 ? "0 pts" : (value > 0 ? "+\(Int(value.rounded())) pts" : "\(Int(value.rounded())) pts"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(value > 0 ? .green : (value < 0 ? .red : .secondary))
            }
            ProgressView(value: magnitude, total: cap)
                .tint(value > 0 ? .green : (value < 0 ? .red : .secondary))
        }
    }

    private var napImpactCard: some View {
        DashboardCard(title: "Nap Impact", systemImage: "zzz") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatChip(label: "Nap time", value: Formatters.napDuration(dayNaps.reduce(0) { $0 + $1.durationMinutes }))
                    StatChip(label: "Naps", value: "\(dayNaps.count)")
                    StatChip(label: "Contribution", value: contributionLabel, color: contributionColor)
                }
                if !log.napExplanations.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(log.napExplanations, id: \.self) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").font(.caption).foregroundStyle(.tertiary)
                                Text(line).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                VStack(spacing: 8) {
                    ForEach(dayNaps, id: \.persistentModelID) { nap in
                        napDetailRow(nap)
                            .contextMenu {
                                Button(role: .destructive) { deleteNap(nap) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }

    private func napDetailRow(_ nap: NapLog) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "zzz")
                .font(.subheadline)
                .foregroundStyle(.mint)
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            Text("\(nap.napStart.formatted(date: .omitted, time: .shortened)) – \(nap.napEnd.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
            Spacer()
            Text(Formatters.napDuration(nap.durationMinutes))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var contributionLabel: String {
        let points = log.napContributionScore
        return points == 0 ? "0" : (points > 0 ? "+\(Int(points.rounded()))" : "\(Int(points.rounded()))")
    }
    private var contributionColor: Color {
        log.napContributionScore > 0 ? .green : (log.napContributionScore < 0 ? .red : .primary)
    }

    /// Deletes a nap and recomputes this log's score from the remaining
    /// same-day naps, so the day's score and this view never drift apart.
    private func deleteNap(_ nap: NapLog) {
        context.delete(nap)
        let remaining = dayNaps.filter { $0.uuid != nap.uuid }
        SleepScoringService.recompute(log, history: allLogs, naps: remaining)
    }
}

// MARK: - Sleep log entry

struct SleepLogEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\SleepLog.date, order: .reverse), SortDescriptor(\SleepLog.createdAt, order: .reverse)])
    private var logs: [SleepLog]
    @Query(sort: \NapLog.napStart) private var naps: [NapLog]

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
        // Always inserts a new log, on purpose — never overwrites an
        // existing one for the same calendar night. An earlier version of
        // this matched by night and updated in place, which sounds like a
        // convenience but is actually a silent, unconfirmed overwrite: it
        // destroyed a just-restored night's real data the moment a new log
        // happened to land on the same calendar day (e.g. an early-morning
        // entry). This app's rule is that nothing gets deleted or replaced
        // without the user seeing it happen — see distinctNights, which
        // instead makes "latest"/average/count correct at display time
        // without ever mutating the store, and Recent Logs' manual delete
        // for genuinely resolving a duplicate.
        let hours = durationHours
        let day = sleepStart.startOfDay
        let sameDayNaps = naps.filter { $0.date == day }
        let result = SleepScoringService.score(sleepStart: sleepStart, sleepEnd: sleepEnd, wakeUps: wakeUps,
                                               history: logs, naps: sameDayNaps, date: sleepStart)
        let log = SleepLog(date: day, sleepStart: sleepStart, sleepEnd: sleepEnd,
                           wakeUps: wakeUps, durationHours: hours, notes: notes)
        SleepScoringService.apply(result, to: log)
        context.insert(log)
        dismiss()
    }
}

// MARK: - Nap log entry

struct NapLogEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\SleepLog.date, order: .reverse), SortDescriptor(\SleepLog.createdAt, order: .reverse)])
    private var logs: [SleepLog]
    @Query(sort: \NapLog.napStart) private var naps: [NapLog]

    @State private var napStart: Date = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var napEnd: Date = Calendar.current.date(bySettingHour: 13, minute: 20, second: 0, of: Date()) ?? Date()
    @State private var notes: String = ""
    @State private var didSave = false

    private var durationMinutes: Double {
        max(0, napEnd.timeIntervalSince(napStart) / 60)
    }

    var body: some View {
        Form {
            Section("Nap Time") {
                DatePicker("Started", selection: $napStart, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Ended", selection: $napEnd, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(Formatters.napDuration(durationMinutes))
                        .foregroundStyle(.secondary)
                }
            }
            Section("Notes") {
                TextField("Optional: where, why, how you felt…", text: $notes, axis: .vertical)
            }
        }
        .navigationTitle("Log Nap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(durationMinutes <= 0 || didSave)
            }
        }
        .keyboardDoneToolbar()
    }

    /// Naps are stored separately from overnight sleep but tagged with the
    /// same calendar day; if that day already has an overnight log, its
    /// score is recomputed immediately so this nap counts right away.
    /// `didSave` guards against a double-tap inserting two NapLog records
    /// for the same nap before the sheet dismisses.
    private func save() {
        guard !didSave else { return }
        didSave = true
        let day = napStart.startOfDay
        let nap = NapLog(date: day, napStart: napStart, napEnd: napEnd, durationMinutes: durationMinutes, notes: notes)
        context.insert(nap)
        if let log = logs.first(where: { $0.date == day }) {
            // `naps` may already reflect the just-inserted nap (SwiftData's
            // @Query can update as soon as context.insert runs), so exclude
            // it by uuid before appending rather than assuming it's absent —
            // otherwise this nap gets counted twice.
            let sameDayNaps = naps.filter { $0.date == day && $0.uuid != nap.uuid } + [nap]
            SleepScoringService.recompute(log, history: logs, naps: sameDayNaps)
        }
        dismiss()
    }
}
