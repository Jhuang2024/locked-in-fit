import SwiftUI
import SwiftData
import Charts

/// Bodyweight scatter + smoothed trend line, body fat %, and quick logging.
struct WeightTrendsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \BodyFatEntry.date) private var bodyFats: [BodyFatEntry]

    @State private var windowDays = 60
    @State private var showLogWeight = false
    @State private var newWeight = ""
    @State private var newBodyFat = ""

    static let allTimeWindow = Int.max

    private var cutoff: Date {
        windowDays == Self.allTimeWindow ? .distantPast : Date().daysAgo(windowDays).startOfDay
    }
    private var chartEnd: Date { Date() }
    private var chartDomain: ClosedRange<Date> {
        let start: Date
        if windowDays == Self.allTimeWindow {
            let earliest = [weights.first?.date, bodyFats.first?.date].compactMap { $0 }.min()
            start = (earliest ?? chartEnd).startOfDay
        } else {
            start = cutoff
        }
        return start...max(chartEnd, start.addingTimeInterval(86400))
    }
    /// For a bounded window, seed the smoothing from entries in that window only;
    /// otherwise an all-time HealthKit import can anchor the EWMA to an old weight
    /// and take dozens of readings to converge back to the present. "All" keeps the
    /// full history since that's the point of viewing it.
    private var trendSourceEntries: [BodyWeightEntry] {
        guard windowDays != Self.allTimeWindow else { return weights }
        let windowed = weights.filter { $0.date >= cutoff }
        return windowed.isEmpty ? weights : windowed
    }
    private var trendPoints: [WeightTrendCalculator.TrendPoint] {
        WeightTrendCalculator.trend(entries: trendSourceEntries).filter { $0.date >= cutoff && $0.date <= chartEnd }
    }
    private var fatPoints: [BodyFatEntry] {
        bodyFats
            .filter { $0.date >= cutoff && $0.date <= chartEnd }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Window", selection: $windowDays) {
                    Text("1M").tag(30)
                    Text("2M").tag(60)
                    Text("6M").tag(180)
                    Text("1Y").tag(365)
                    Text("All").tag(Self.allTimeWindow)
                }
                .pickerStyle(.segmented)

                if let last = trendPoints.last {
                    HStack {
                        StatChip(label: "Trend weight", value: Formatters.kg(last.trendKg), color: .blue)
                        StatChip(label: "Last scale", value: Formatters.kg(last.weightKg), color: .blue)
                        let rate = WeightTrendCalculator.weeklyChangeFromEntries(entries: weights)
                        StatChip(label: "Per week", value: rate.map { Formatters.kgChange($0) } ?? "Not enough data",
                                 color: rate != nil ? .blue : .secondary)
                    }
                    .padding(14)
                    .cardBackground()
                }

                if trendPoints.isEmpty {
                    DashboardCard(title: "Bodyweight", systemImage: "scalemass") {
                        EmptyStateView(systemImage: "scalemass", title: "Connect HealthKit or enter weight manually", message: "Your trend appears once you have weigh-ins.")
                    }
                } else {
                    ChartCard(title: "Bodyweight", subtitle: "Dots are scale readings; the line is your smoothed trend.") {
                        Chart {
                            ForEach(trendPoints) { point in
                                AreaMark(x: .value("Date", point.date), y: .value("kg", point.trendKg))
                                    .foregroundStyle(.linearGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
                                                                      startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.monotone)
                            }
                            ForEach(trendPoints) { point in
                                PointMark(x: .value("Date", point.date), y: .value("kg", point.weightKg))
                                    .foregroundStyle(Color.accentColor.opacity(0.35))
                                    .symbolSize(24)
                            }
                            ForEach(trendPoints) { point in
                                LineMark(x: .value("Date", point.date), y: .value("kg", point.trendKg))
                                    .foregroundStyle(Color.accentColor)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                                    .interpolationMethod(.monotone)
                            }
                        }
                        .id("weight-\(windowDays)")
                        .chartXScale(domain: chartDomain)
                        .chartYScale(domain: .automatic(includesZero: false))
                    }
                }

                if !fatPoints.isEmpty {
                    ChartCard(title: "Body Fat %", subtitle: "From Renpho via Apple Health, or manual entries.") {
                        Chart(fatPoints) { entry in
                            LineMark(x: .value("Date", entry.date), y: .value("%", entry.bodyFatPercentage))
                                .foregroundStyle(Color.orange)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", entry.date), y: .value("%", entry.bodyFatPercentage))
                                .foregroundStyle(Color.orange.opacity(0.5))
                                .symbolSize(20)
                        }
                        .id("fat-\(windowDays)")
                        .chartXScale(domain: chartDomain)
                        .chartYScale(domain: .automatic(includesZero: false))
                    }
                }

                recentEntries
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .brandScreenBackground()
        .navigationTitle("Weight Trends")
        .toolbar {
            Button { showLogWeight = true } label: { Image(systemName: "plus") }
        }
        .alert("Log Weigh-In", isPresented: $showLogWeight) {
            TextField("Weight (kg)", text: $newWeight)
                .keyboardType(.decimalPad)
            TextField("Body fat % (optional)", text: $newBodyFat)
                .keyboardType(.decimalPad)
            Button("Save") { saveEntry() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var recentEntries: some View {
        DashboardCard(title: "Recent Entries", systemImage: "scalemass") {
            if weights.isEmpty {
                EmptyStateView(systemImage: "scalemass", title: "No weigh-ins yet", message: "Log weight manually or sync Apple Health.")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(weights.suffix(7).reversed()), id: \.persistentModelID) { entry in
                        HStack {
                            Text(Formatters.mediumDate(entry.date))
                                .font(.subheadline)
                            Spacer()
                            Text(entry.source.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Formatters.kg(entry.weightKg))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private func saveEntry() {
        if let kg = Double(newWeight), kg > 20, kg < 300 {
            context.insert(BodyWeightEntry(date: .now, weightKg: kg, source: .manual))
            Task { await HealthKitManager.shared.writeWeight(kg, date: .now) }
        }
        if let bf = Double(newBodyFat), bf > 3, bf < 60 {
            context.insert(BodyFatEntry(date: .now, bodyFatPercentage: bf, source: .manual))
        }
        newWeight = ""; newBodyFat = ""
    }
}
