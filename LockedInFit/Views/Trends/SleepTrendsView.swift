import SwiftUI
import SwiftData
import Charts

/// Sleep score and duration over time, matching AppearanceTrendsView's chart
/// style and windowed-picker pattern. Backed entirely by persisted SleepLog
/// data, so it updates the moment a new sleep log is saved.
struct SleepTrendsView: View {
    @Query(sort: \SleepLog.date) private var logs: [SleepLog]
    @Query(sort: \NapLog.napStart) private var naps: [NapLog]

    @State private var windowDays = 30
    @State private var selectedScoreDate: Date?
    @State private var selectedDurationDate: Date?
    @State private var selectedBreakdownDate: Date?

    static let allTimeWindow = Int.max

    private var cutoff: Date {
        windowDays == Self.allTimeWindow ? .distantPast : Date().daysAgo(windowDays).startOfDay
    }
    private var windowedLogs: [SleepLog] { logs.filter { $0.date >= cutoff } }
    private var windowedNaps: [NapLog] { naps.filter { $0.date >= cutoff } }
    /// Forces the charts below to always span the full requested window
    /// (today back to `cutoff`), rather than auto-fitting to just the dates
    /// that happen to have logs. With only a couple of points, auto-fit
    /// shrinks the domain to the gap between them: if that gap is under a
    /// day, Swift Charts' automatic axis then labels it by hour (12 AM, 6
    /// AM, ...) with no date shown at all, making two different, correctly
    /// dated nights unreadable as anything but "today-ish". A domain that
    /// always spans real days makes the axis fall back to date labels.
    private var chartDomainStart: Date {
        windowDays == Self.allTimeWindow ? (windowedLogs.map(\.date).min() ?? Date().daysAgo(1)) : cutoff
    }
    private var chartDomainEnd: Date { Date() }
    private var scorePoints: [(date: Date, score: Double)] {
        windowedLogs.map { (date: $0.date, score: $0.totalScore) }
    }
    private var durationPoints: [(date: Date, hours: Double)] {
        windowedLogs.map { (date: $0.date, hours: $0.durationHours) }
    }
    private var totalNapMinutes: Double { windowedNaps.reduce(0) { $0 + $1.durationMinutes } }
    private var napDayCount: Int { Set(windowedNaps.map { $0.date }).count }
    private var avgNapContribution: Double? {
        let withNaps = windowedLogs.filter { $0.napContributionScore != 0 }
        guard !withNaps.isEmpty else { return nil }
        return withNaps.reduce(0.0) { $0 + $1.napContributionScore } / Double(withNaps.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Window", selection: $windowDays) {
                    Text("7D").tag(7)
                    Text("30D").tag(30)
                    Text("90D").tag(90)
                    Text("All").tag(Self.allTimeWindow)
                }
                .pickerStyle(.segmented)

                scoreChart
                durationChart
                if windowedLogs.count >= 3 {
                    breakdownChart
                }
                statsSection
                napSummarySection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .brandScreenBackground()
        .navigationTitle("Sleep Trends")
    }

    // MARK: - Charts

    @ViewBuilder
    private var scoreChart: some View {
        if scorePoints.isEmpty {
            DashboardCard(title: "Sleep Score", systemImage: "chart.xyaxis.line") {
                EmptyStateView(systemImage: "chart.xyaxis.line", title: "No data in this window",
                               message: "Sleep scores appear once you log a night's sleep.")
            }
        } else {
            ChartCard(title: "Sleep Score", subtitle: "0–100 · duration, consistency, interruptions, timing · tap or drag for the exact score") {
                Chart {
                    ForEach(Array(scorePoints.enumerated()), id: \.offset) { _, point in
                        AreaMark(x: .value("Date", point.date), y: .value("Score", point.score))
                            .foregroundStyle(.linearGradient(colors: [.indigo.opacity(0.28), .indigo.opacity(0.02)],
                                                              startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Date", point.date), y: .value("Score", point.score))
                            .foregroundStyle(.indigo)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", point.date), y: .value("Score", point.score))
                            .foregroundStyle(Color.indigo.opacity(0.5))
                            .symbolSize(24)
                    }
                    if let point = nearestScorePoint(to: selectedScoreDate) {
                        RuleMark(x: .value("Selected date", point.date))
                            .foregroundStyle(.secondary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .zIndex(10)
                            .annotation(
                                position: .top,
                                spacing: 4,
                                overflowResolution: .init(
                                    x: .fit(to: .chart),
                                    y: .fit(to: .chart)
                                )
                            ) {
                                ChartPointCallout(date: point.date, values: [
                                    ("Sleep score", Formatters.trimmed(point.score))
                                ])
                            }
                        PointMark(x: .value("Selected date", point.date),
                                  y: .value("Selected score", point.score))
                            .foregroundStyle(Color.indigo)
                            .symbolSize(70)
                    }
                }
                .id("score-\(windowDays)")
                .chartYScale(domain: 0.0...100.0)
                .chartXScale(domain: chartDomainStart...chartDomainEnd)
                .chartXAxis { dateAxisMarks }
                .chartXSelection(value: $selectedScoreDate)
            }
        }
    }

    @ViewBuilder
    private var durationChart: some View {
        if !durationPoints.isEmpty {
            ChartCard(title: "Sleep Duration", subtitle: "Hours asleep per night · 7–9h target · tap or drag for the exact value") {
                Chart {
                    ForEach(Array(durationPoints.enumerated()), id: \.offset) { _, point in
                        BarMark(x: .value("Date", point.date), y: .value("Hours", point.hours))
                            .foregroundStyle(Color.teal.gradient)
                    }
                    if let point = nearestDurationPoint(to: selectedDurationDate) {
                        RuleMark(x: .value("Selected date", point.date))
                            .foregroundStyle(.secondary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .zIndex(10)
                            .annotation(
                                position: .top,
                                spacing: 4,
                                overflowResolution: .init(
                                    x: .fit(to: .chart),
                                    y: .fit(to: .chart)
                                )
                            ) {
                                ChartPointCallout(date: point.date, values: [
                                    ("Sleep", "\(Formatters.trimmed(point.hours)) h")
                                ])
                            }
                        PointMark(x: .value("Selected date", point.date),
                                  y: .value("Selected duration", point.hours))
                            .foregroundStyle(Color.teal)
                            .symbolSize(70)
                    }
                }
                .id("duration-\(windowDays)")
                .chartYScale(domain: 0.0...12.0)
                .chartXScale(domain: chartDomainStart...chartDomainEnd)
                .chartXAxis { dateAxisMarks }
                .chartXSelection(value: $selectedDurationDate)
            }
        }
    }

    /// Ticks always land exactly on a calendar-day boundary, at a stride
    /// chosen to land roughly 5 of them across the domain. `.automatic`
    /// picks evenly time-spaced ticks instead, which for a domain under
    /// ~10 days lands more than one tick inside the same calendar day,
    /// with a day-only format that prints the same date twice in a row.
    /// A whole-day stride can't produce two ticks on the same day.
    private var axisDayStride: Int {
        let totalDays = Calendar.current.dateComponents([.day], from: chartDomainStart, to: chartDomainEnd).day ?? 1
        return max(1, totalDays / 5)
    }

    private var dateAxisMarks: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: axisDayStride)) { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
        }
    }

    private var breakdownChart: some View {
        ChartCard(title: "Sleep Score Breakdown", subtitle: "Component points over time · tap or drag for exact values") {
            Chart {
                ForEach(Array(windowedLogs.enumerated()), id: \.offset) { _, log in
                    LineMark(x: .value("Date", log.date), y: .value("Points", log.durationScore),
                             series: .value("Component", "Duration"))
                        .foregroundStyle(by: .value("Component", "Duration"))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", log.date), y: .value("Points", log.consistencyScore),
                             series: .value("Component", "Consistency"))
                        .foregroundStyle(by: .value("Component", "Consistency"))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", log.date), y: .value("Points", log.interruptionScore),
                             series: .value("Component", "Interruptions"))
                        .foregroundStyle(by: .value("Component", "Interruptions"))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", log.date), y: .value("Points", log.timingScore),
                             series: .value("Component", "Timing"))
                        .foregroundStyle(by: .value("Component", "Timing"))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let log = nearestBreakdownLog(to: selectedBreakdownDate) {
                    RuleMark(x: .value("Selected date", log.date))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .zIndex(10)
                        .annotation(
                            position: .top,
                            spacing: 4,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .fit(to: .chart)
                            )
                        ) {
                            ChartPointCallout(date: log.date, values: [
                                ("Duration", Formatters.trimmed(log.durationScore)),
                                ("Consistency", Formatters.trimmed(log.consistencyScore)),
                                ("Interruptions", Formatters.trimmed(log.interruptionScore)),
                                ("Timing", Formatters.trimmed(log.timingScore))
                            ])
                        }
                    PointMark(x: .value("Selected date", log.date),
                              y: .value("Selected duration", log.durationScore))
                        .foregroundStyle(by: .value("Component", "Duration"))
                        .symbolSize(58)
                    PointMark(x: .value("Selected date", log.date),
                              y: .value("Selected consistency", log.consistencyScore))
                        .foregroundStyle(by: .value("Component", "Consistency"))
                        .symbolSize(58)
                    PointMark(x: .value("Selected date", log.date),
                              y: .value("Selected interruptions", log.interruptionScore))
                        .foregroundStyle(by: .value("Component", "Interruptions"))
                        .symbolSize(58)
                    PointMark(x: .value("Selected date", log.date),
                              y: .value("Selected timing", log.timingScore))
                        .foregroundStyle(by: .value("Component", "Timing"))
                        .symbolSize(58)
                }
            }
            .id("breakdown-\(windowDays)")
            .chartYScale(domain: 0.0...40.0)
            .chartXScale(domain: chartDomainStart...chartDomainEnd)
            .chartXAxis { dateAxisMarks }
            .chartXSelection(value: $selectedBreakdownDate)
        }
    }

    private func nearestScorePoint(to date: Date?) -> (date: Date, score: Double)? {
        guard let date else { return nil }
        return scorePoints.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func nearestDurationPoint(to date: Date?) -> (date: Date, hours: Double)? {
        guard let date else { return nil }
        return durationPoints.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func nearestBreakdownLog(to date: Date?) -> SleepLog? {
        guard let date else { return nil }
        return windowedLogs.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        if !windowedLogs.isEmpty {
            let avgScore = windowedLogs.reduce(0.0) { $0 + $1.totalScore } / Double(windowedLogs.count)
            let avgDuration = windowedLogs.reduce(0.0) { $0 + $1.durationHours } / Double(windowedLogs.count)
            let avgWakeUps = Double(windowedLogs.reduce(0) { $0 + $1.wakeUps }) / Double(windowedLogs.count)
            DashboardCard(title: "Window Averages", systemImage: "chart.bar") {
                HStack {
                    StatChip(label: "Avg score", value: "\(Int(avgScore.rounded()))",
                             color: avgScore >= 70 ? .green : avgScore >= 50 ? .orange : .red)
                    StatChip(label: "Avg duration", value: "\(Formatters.trimmed(avgDuration))h",
                             color: (avgDuration >= 7 && avgDuration <= 9.5) ? .green : avgDuration >= 6 ? .orange : .red)
                    StatChip(label: "Avg wake-ups", value: String(format: "%.1f", avgWakeUps),
                             color: avgWakeUps <= 1 ? .green : avgWakeUps <= 3 ? .orange : .red)
                }
            }
            let times = SleepScoringService.averageTimes(for: windowedLogs)
            DashboardCard(title: "Sleep Times", systemImage: "clock") {
                SleepTimesTable(bedtime: times.bedtime, wake: times.wake)
            }
        }
    }

    @ViewBuilder
    private var napSummarySection: some View {
        if !windowedNaps.isEmpty {
            DashboardCard(title: "Naps", systemImage: "zzz") {
                HStack {
                    StatChip(label: "Total nap time", value: Formatters.napDuration(totalNapMinutes), color: .blue)
                    StatChip(label: "Days napped", value: "\(napDayCount)", color: .blue)
                    if let avgNapContribution {
                        StatChip(label: "Avg impact", value: avgNapContribution >= 0 ? "+\(Int(avgNapContribution.rounded()))" : "\(Int(avgNapContribution.rounded()))",
                                 color: avgNapContribution > 0 ? .green : (avgNapContribution < 0 ? .red : .primary))
                    }
                }
            }
        }
    }
}
