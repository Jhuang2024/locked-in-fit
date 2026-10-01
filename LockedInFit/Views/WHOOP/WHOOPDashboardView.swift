import SwiftUI
import SwiftData
import Charts

private let whoopRecordsDescriptor = FetchDescriptor<WHOOPRecord>(sortBy: [SortDescriptor(\WHOOPRecord.date, order: .reverse)])

enum WHOOPRoute: Hashable { case overview }

struct WHOOPSummaryCard: View {
    @Query(whoopRecordsDescriptor) private var records: [WHOOPRecord]
    private var recovery: WHOOPRecord? { records.first { $0.kind == "recovery" } }
    private var sleep: WHOOPRecord? { records.first { $0.kind == "sleep" && !$0.isNap } }
    private var cycle: WHOOPRecord? { records.first { $0.kind == "cycle" } }

    var body: some View {
        NavigationLink(value: SettingsRoute.whoop) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("WHOOP", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.bold)).tracking(1.5)
                    Spacer()
                    Text(records.isEmpty ? "Connect" : "Recovery & health").font(.caption)
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                }
                if records.isEmpty {
                    Text("Your recovery, in context.").font(.title3.weight(.semibold))
                    Text("Bring sleep, strain, heart health and workouts into your daily overview.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        StatChip(label: "Recovery", value: recovery?.recovery.map { "\(Int($0))%" } ?? "—", color: recoveryColor)
                        StatChip(label: "Strain", value: cycle?.strain.map { String(format: "%.1f", $0) } ?? "—")
                        StatChip(label: "Asleep", value: sleep?.sleepHours.map { String(format: "%.1f h", $0) } ?? "—")
                    }
                    if let date = recovery?.date {
                        Text("Recovery cycle • \(Formatters.mediumDate(date))\(Date().timeIntervalSince(date) > 172800 ? " • Older reading" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .foregroundStyle(.primary).padding(CardMetrics.padding).cardBackground()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("WHOOP recovery and health. Open overview")
    }
    private var recoveryColor: Color {
        guard let score = recovery?.recovery else { return .secondary }
        return score >= 67 ? .green : score >= 34 ? .yellow : .red
    }
}

struct WHOOPDashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(whoopRecordsDescriptor) private var records: [WHOOPRecord]
    @State private var service = WHOOPService.shared
    @State private var broker = ""
    @State private var showDisconnect = false
    @State private var showDelete = false
    @State private var selectedMetric = "recovery"
    @State private var selectedDate: Date?
    @State private var days = 30

    private func latest(_ kind: String) -> WHOOPRecord? {
        records.first { $0.kind == kind && (kind != "sleep" || !$0.isNap) }
    }
    private var recovery: WHOOPRecord? { latest("recovery") }
    private var sleep: WHOOPRecord? { latest("sleep") }
    private var cycle: WHOOPRecord? { latest("cycle") }
    private var bodyRecord: WHOOPRecord? { latest("body") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CardMetrics.spacing) {
                connectionCard
                if !records.isEmpty {
                    recoveryCard
                    trendCard
                    vitalsCard
                    sleepCard
                    cycleCard
                    workoutsCard
                    bodyCard
                }
                availabilityCard
            }
            .padding().padding(.bottom, 24)
        }
        .brandScreenBackground()
        .navigationTitle("WHOOP")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await service.sync(context: context, days: days) }
        .task { broker = service.brokerURL; await service.syncIfNeeded(context: context) }
        .confirmationDialog("Disconnect WHOOP? Imported history remains saved.", isPresented: $showDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await service.disconnect() } }
        }
        .confirmationDialog("Delete imported WHOOP history from this device? Your manual logs remain saved.", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete WHOOP History", role: .destructive) {
                do {
                    for record in records { context.delete(record) }
                    try context.save()
                    UserDefaults.standard.removeObject(forKey: "whoopLastSync")
                    service.message = "WHOOP history deleted. Existing backups may still contain it."
                } catch { service.message = error.localizedDescription }
            }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconBadge(systemImage: "waveform.path.ecg", size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.isConnected ? "WHOOP connected" : "Connect your WHOOP").font(.headline)
                    if let date = service.lastSync {
                        Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    } else { Text("Recovery • Sleep • Strain • Vitals").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if service.syncing || service.connecting { ProgressView() }
            }
            if !service.isConnected {
                Text("Use the HTTPS connector URL from your WHOOP integration setup. Authorize your account in WHOOP; credentials are stored in Keychain.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("https://your-whoop-connector.example", text: $broker)
                    .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    service.brokerURL = broker
                    Task { await service.connect(context: context) }
                } label: { Label("Connect WHOOP", systemImage: "link").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(broker.isEmpty || service.connecting || service.syncing)
            } else {
                Picker("History window", selection: $days) {
                    Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365)
                }.pickerStyle(.segmented)
                HStack {
                    Button { Task { await service.sync(context: context, days: days) } } label: { Label("Sync now", systemImage: "arrow.clockwise") }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Disconnect", role: .destructive) { showDisconnect = true }.font(.caption)
                }.disabled(service.syncing || service.connecting)
            }
            if let message = service.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if !records.isEmpty {
                Button("Delete imported history", role: .destructive) { showDelete = true }.font(.caption)
                    .disabled(service.syncing || service.connecting)
            }
        }.padding(CardMetrics.padding).heroCardBackground()
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Recovery", record: recovery, icon: "heart.circle")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(recovery?.recovery.map { "\(Int($0))" } ?? "—")
                    .font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("/ 100").foregroundStyle(.secondary)
                Spacer()
                Text(recoveryLabel).font(.subheadline.weight(.semibold)).foregroundStyle(recoveryColor)
            }
            if let score = recovery?.recovery { ProgressView(value: score, total: 100).tint(recoveryColor) }
            Text(recovery?.payload["score_state"] as? String == "SCORED" ? "Use recovery alongside how you feel and your training plan." : "WHOOP is still processing this cycle. Missing scores are not zero.")
                .font(.caption).foregroundStyle(.secondary)
            if recovery?.payload["score"] as? [String: Any] != nil,
               (recovery?.payload["score"] as? [String: Any])?["user_calibrating"] as? Bool == true {
                Label("WHOOP is calibrating your baseline", systemImage: "hourglass").font(.caption)
            }
        }.padding(CardMetrics.padding).cardBackground()
    }
    private var recoveryLabel: String {
        guard let value = recovery?.recovery else { return "Pending" }
        return value >= 67 ? "Recovered" : value >= 34 ? "Moderate" : "Low recovery"
    }
    private var recoveryColor: Color {
        guard let value = recovery?.recovery else { return .secondary }
        return value >= 67 ? .green : value >= 34 ? .yellow : .red
    }

    private var vitalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Health monitor", record: recovery, icon: "waveform.path.ecg")
            metric("HRV", recovery, "score.hrv_rmssd_milli", unit: "ms")
            metric("Resting heart rate", recovery, "score.resting_heart_rate", unit: "bpm")
            metric("Blood oxygen", recovery, "score.spo2_percentage", unit: "%")
            metric("Skin temperature", recovery, "score.skin_temp_celsius", unit: "°C")
            metric("Respiratory rate", sleep, "score.respiratory_rate", unit: "breaths/min")
            Text("Respiratory rate belongs to the sleep shown below. Skin temperature is a skin measurement, not core body temperature.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(CardMetrics.padding).cardBackground()
    }

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Sleep architecture", record: sleep, icon: "moon.stars")
            if let start = WHOOPData.date(sleep?.payload["start"]), let end = WHOOPData.date(sleep?.payload["end"]) {
                Text("\(start.formatted(date: .abbreviated, time: .shortened)) → \(end.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            metric("Time asleep", value: sleep?.sleepHours, unit: "h")
            metric("Time in bed", sleep, "score.stage_summary.total_in_bed_time_milli", unit: "min", divisor: 60_000)
            ForEach([("Light", "total_light_sleep_time_milli"), ("Deep", "total_slow_wave_sleep_time_milli"), ("REM", "total_rem_sleep_time_milli"), ("Awake", "total_awake_time_milli"), ("No data", "total_no_data_time_milli")], id: \.0) { label, key in
                metric(label, sleep, "score.stage_summary.\(key)", unit: "min", divisor: 60_000)
            }
            metric("Performance", sleep, "score.sleep_performance_percentage", unit: "%")
            metric("Consistency", sleep, "score.sleep_consistency_percentage", unit: "%")
            metric("Efficiency", sleep, "score.sleep_efficiency_percentage", unit: "%")
            metric("Sleep cycles", sleep, "score.stage_summary.sleep_cycle_count", unit: "", decimals: 0)
            metric("Disturbances", sleep, "score.stage_summary.disturbance_count", unit: "", decimals: 0)
            Divider()
            Text("Sleep need").font(.subheadline.weight(.semibold))
            ForEach([("Baseline", "baseline_milli"), ("Sleep debt", "need_from_sleep_debt_milli"), ("Recent strain", "need_from_recent_strain_milli"), ("Nap adjustment", "need_from_recent_nap_milli")], id: \.0) { label, key in
                metric(label, sleep, "score.sleep_needed.\(key)", unit: "min", divisor: 60_000)
            }
            let naps = records.filter { $0.kind == "sleep" && $0.isNap }.prefix(5)
            if !naps.isEmpty {
                Divider(); Text("Recent naps").font(.subheadline.weight(.semibold))
                ForEach(Array(naps), id: \.key) { nap in
                    metric(Formatters.mediumDate(nap.date), value: nap.sleepHours.map { $0 * 60 }, unit: "min")
                }
            }
            Text("WHOOP sleep uses measured stages and wake dates. Manual sleep logs keep their original scoring and night dates.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(CardMetrics.padding).cardBackground()
    }

    private var cycleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Physiological cycle", record: cycle, icon: "bolt.heart")
            metric("Day strain", value: cycle?.strain, unit: "/ 21")
            metric("Total energy", value: cycle?.isScored == true ? cycle?.number("score.kilojoule").map(WHOOPData.kcal) : nil, unit: "kcal", decimals: 0)
            metric("Average heart rate", cycle, "score.average_heart_rate", unit: "bpm")
            metric("Maximum heart rate", cycle, "score.max_heart_rate", unit: "bpm")
            metric("Cycle steps", value: cycle?.number("step_count"), unit: "", decimals: 0)
            Text("A WHOOP cycle can cross midnight. Its energy includes resting energy; it is not added to your active-calorie allowance or Apple Health totals.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(CardMetrics.padding).cardBackground()
    }

    private var workoutsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Recorded workouts", systemImage: "figure.strengthtraining.traditional").font(.headline)
            let workouts = records.filter { $0.kind == "workout" }.prefix(20)
            if workouts.isEmpty { Text("No WHOOP workouts in your synced history.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(workouts), id: \.key) { workout in
                DisclosureGroup {
                    metric("Strain", value: workout.strain, unit: "/ 21")
                    metric("Energy", value: workout.isScored ? workout.number("score.kilojoule").map(WHOOPData.kcal) : nil, unit: "kcal", decimals: 0)
                    metric("Average heart rate", workout, "score.average_heart_rate", unit: "bpm")
                    metric("Maximum heart rate", workout, "score.max_heart_rate", unit: "bpm")
                    metric("Recorded", workout, "score.percent_recorded", unit: "%")
                    metric("Distance", workout, "score.distance_meter", unit: "m", decimals: 0)
                    metric("Elevation gain", workout, "score.altitude_gain_meter", unit: "m")
                    metric("Elevation change", workout, "score.altitude_change_meter", unit: "m")
                    ForEach(Array(["zero", "one", "two", "three", "four", "five"].enumerated()), id: \.offset) { index, zone in
                        metric("Heart rate zone \(index)", workout, "score.zone_durations.zone_\(zone)_milli", unit: "min", divisor: 60_000)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((workout.payload["sport_name"] as? String ?? "Workout").replacingOccurrences(of: "_", with: " ").capitalized).font(.subheadline.weight(.semibold))
                        Text(workout.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        if let start = WHOOPData.date(workout.payload["start"]), let end = WHOOPData.date(workout.payload["end"]) {
                            Text("\(Int(max(0, end.timeIntervalSince(start)) / 60)) min").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
            }
            Text("Imported workouts are separate from your set-by-set training log, so syncing cannot duplicate sessions or calories.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(CardMetrics.padding).cardBackground()
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("WHOOP body profile", record: bodyRecord, icon: "person.crop.circle")
            metric("Height", value: bodyRecord?.number("height_meter").map { $0 * 100 }, unit: "cm")
            metric("Profile weight", value: bodyRecord?.number("weight_kilogram"), unit: "kg")
            metric("Maximum heart rate", value: bodyRecord?.number("max_heart_rate"), unit: "bpm", decimals: 0)
            Text("Profile measurements are not dated scale readings and do not overwrite your weigh-ins or settings.").font(.caption).foregroundStyle(.secondary)
        }.padding(CardMetrics.padding).cardBackground()
    }

    private var availabilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Data availability", systemImage: "info.circle").font(.headline)
            Text("Recovery, HRV, resting heart rate, blood oxygen, skin temperature, sleep stages, sleep need, respiratory rate, strain, cycle steps, energy and workout heart-rate zones sync through WHOOP API v2 when available.").font(.caption).foregroundStyle(.secondary)
            Text("WHOOP's public API does not currently expose Stress Monitor, Healthspan / WHOOP Age, Pace of Aging or journal insights. They are unavailable here. A dash means missing or still processing, never zero.").font(.caption).foregroundStyle(.secondary)
            Link("WHOOP API documentation", destination: URL(string: "https://developer.whoop.com/api/")!).font(.caption)
        }.padding(CardMetrics.padding).cardBackground()
    }

    private struct TrendMetric: Identifiable {
        let id: String; let label: String; let kind: String; let path: String; let unit: String
    }
    private let metrics: [TrendMetric] = [
        .init(id: "recovery", label: "Recovery", kind: "recovery", path: "score.recovery_score", unit: "%"),
        .init(id: "hrv", label: "HRV", kind: "recovery", path: "score.hrv_rmssd_milli", unit: "ms"),
        .init(id: "rhr", label: "Resting HR", kind: "recovery", path: "score.resting_heart_rate", unit: "bpm"),
        .init(id: "spo2", label: "Blood oxygen", kind: "recovery", path: "score.spo2_percentage", unit: "%"),
        .init(id: "temp", label: "Skin temperature", kind: "recovery", path: "score.skin_temp_celsius", unit: "°C"),
        .init(id: "strain", label: "Day strain", kind: "cycle", path: "score.strain", unit: "/21"),
        .init(id: "sleep", label: "Sleep performance", kind: "sleep", path: "score.sleep_performance_percentage", unit: "%"),
        .init(id: "resp", label: "Respiratory rate", kind: "sleep", path: "score.respiratory_rate", unit: "breaths/min")
    ]
    private struct TrendPoint: Identifiable {
        let id: String; let date: Date; let value: Double
    }
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your baseline").font(.headline)
                Spacer()
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(metrics) { Text($0.label).tag($0.id) }
                }.labelsHidden()
            }
            if let metric = metrics.first(where: { $0.id == selectedMetric }) {
                let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
                let points = records.filter { $0.kind == metric.kind && $0.isScored && !$0.isNap && $0.date >= cutoff }
                    .compactMap { record in record.number(metric.path).map { TrendPoint(id: record.key, date: record.date, value: $0) } }
                    .sorted { $0.date < $1.date }
                if points.isEmpty { Text("No scored readings for this metric yet.").font(.subheadline).foregroundStyle(.secondary) }
                else {
                    let selected = selectedDate.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
                    if let selected {
                        Text("\(Formatters.mediumDate(selected.date)) • \(String(format: "%.1f", selected.value)) \(metric.unit)")
                            .font(.caption).monospacedDigit()
                    }
                    Chart(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(metric.label, point.value)).foregroundStyle(BrandPalette.accent)
                        PointMark(x: .value("Date", point.date), y: .value(metric.label, point.value)).foregroundStyle(BrandPalette.accent)
                        if let selected, selected.id == point.id {
                            RuleMark(x: .value("Selected", point.date)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [4]))
                        }
                    }
                    .chartXSelection(value: $selectedDate).frame(height: 180)
                    .accessibilityLabel("\(metric.label) history, \(points.count) readings")
                }
            }
        }.padding(CardMetrics.padding).cardBackground()
        .onChange(of: selectedMetric) { _, _ in selectedDate = nil }
    }

    private func cardHeader(_ title: String, record: WHOOPRecord?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.headline)
            if let record { Text(Formatters.mediumDate(record.date)).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func metric(_ label: String, _ record: WHOOPRecord?, _ path: String, unit: String, divisor: Double = 1, decimals: Int = 1) -> some View {
        metric(label, value: record?.isScored == true ? record?.number(path).map { $0 / divisor } : nil, unit: unit, decimals: decimals)
    }
    private func metric(_ label: String, value: Double?, unit: String, decimals: Int = 1) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value.map { String(format: "%.*f", decimals, $0) + (unit.isEmpty ? "" : " \(unit)") } ?? "—")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }
}

/// Contextual entry point shared by Sleep, Train and Trends. Uses a lazy route
/// so the destination's queries do not run until navigation happens.
struct WHOOPContextLink: View {
    @Query(whoopRecordsDescriptor) private var records: [WHOOPRecord]
    var body: some View {
        if !records.isEmpty {
            NavigationLink(value: WHOOPRoute.overview) {
                HStack(spacing: 12) {
                    IconBadge(systemImage: "waveform.path.ecg")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WHOOP insights").font(.subheadline.weight(.semibold))
                        Text("Recovery, measured sleep and recorded workouts").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                }.foregroundStyle(.primary).padding(CardMetrics.padding).cardBackground()
            }.buttonStyle(.plain)
        }
    }
}
