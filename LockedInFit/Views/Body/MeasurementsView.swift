import SwiftUI
import SwiftData
import Charts

struct MeasurementsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MeasurementEntry.date) private var entries: [MeasurementEntry]
    @State private var showNew = false
    @State private var selectedWaistDate: Date?

    private var waistPoints: [(date: Date, value: Double)] {
        entries.compactMap { entry in entry.waist.map { (entry.date, $0) } }
    }

    var body: some View {
        List {
            if !waistPoints.isEmpty {
                Section {
                    ChartCard(title: "Waist", subtitle: "cm over time · tap or drag for the exact value") {
                        Chart {
                            ForEach(waistPoints, id: \.date) { point in
                                LineMark(x: .value("Date", point.date), y: .value("cm", point.value))
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("Date", point.date), y: .value("cm", point.value))
                                    .symbolSize(24)
                            }
                            if let point = nearestWaistPoint(to: selectedWaistDate) {
                                RuleMark(x: .value("Selected date", point.date))
                                    .foregroundStyle(.secondary.opacity(0.45))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    .annotation(
                                        position: .top,
                                        spacing: 4,
                                        overflowResolution: .init(
                                            x: .fit(to: .chart),
                                            y: .fit(to: .chart)
                                        )
                                    ) {
                                        ChartPointCallout(date: point.date, values: [
                                            ("Waist", "\(Formatters.trimmed(point.value)) cm")
                                        ])
                                    }
                                PointMark(x: .value("Selected date", point.date),
                                          y: .value("Selected waist", point.value))
                                    .symbolSize(70)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXSelection(value: $selectedWaistDate)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section("History") {
                if entries.isEmpty {
                    EmptyStateView(systemImage: "ruler", title: "No measurements yet",
                                   message: "Log waist, chest, arms and more to track body recomposition.")
                }
                ForEach(entries.reversed()) { entry in
                    NavigationLink(destination: MeasurementEditorView(entry: entry)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Formatters.mediumDate(entry.date))
                                .font(.subheadline.weight(.semibold))
                            Text(summary(entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let reversed = Array(entries.reversed())
                    for index in offsets { context.delete(reversed[index]) }
                }
            }
        }
        .navigationTitle("Measurements")
        .toolbar {
            Button { showNew = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack { MeasurementEditorView(entry: nil) }
        }
    }

    private func nearestWaistPoint(to date: Date?) -> (date: Date, value: Double)? {
        guard let date else { return nil }
        return waistPoints.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func summary(_ entry: MeasurementEntry) -> String {
        var parts: [String] = []
        for field in MeasurementEntry.standardFields {
            if let value = entry[keyPath: field.keyPath] {
                parts.append("\(field.label) \(String(format: "%.1f", value))")
            }
        }
        for (key, value) in entry.customMeasurements.sorted(by: { $0.key < $1.key }) {
            parts.append("\(key) \(String(format: "%.1f", value))")
        }
        return parts.isEmpty ? "Empty entry" : parts.joined(separator: " · ")
    }
}

struct MeasurementEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let entry: MeasurementEntry?

    @State private var date = Date()
    @State private var values: [String: String] = [:]
    @State private var customName = ""
    @State private var customValue = ""
    @State private var custom: [String: Double] = [:]
    @State private var notes = ""

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            Section("Measurements (cm)") {
                ForEach(MeasurementEntry.standardFields, id: \.key) { field in
                    HStack {
                        Text(field.label)
                        Spacer()
                        TextField("cm", text: Binding(
                            get: { values[field.key] ?? "" },
                            set: { values[field.key] = $0 }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            Section("Custom") {
                ForEach(custom.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(String(format: "%.1f", value))
                    }
                }
                HStack {
                    TextField("Name (e.g. calf)", text: $customName)
                    TextField("cm", text: $customValue)
                        .keyboardType(.decimalPad)
                        .frame(width: 70)
                    Button("Add") {
                        if let value = Double(customValue), !customName.isEmpty {
                            custom[customName.lowercased()] = value
                            customName = ""; customValue = ""
                        }
                    }
                }
            }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
            }
        }
        .navigationTitle(entry == nil ? "New Measurement" : "Edit Measurement")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            if entry == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear { load() }
    }

    private func load() {
        guard let entry else { return }
        date = entry.date
        for field in MeasurementEntry.standardFields {
            if let value = entry[keyPath: field.keyPath] {
                values[field.key] = String(format: "%.1f", value)
            }
        }
        custom = entry.customMeasurements
        notes = entry.notes
    }

    private func save() {
        let target = entry ?? MeasurementEntry(date: date)
        if entry == nil { context.insert(target) }
        target.date = date
        var mutable = target
        for field in MeasurementEntry.standardFields {
            mutable[keyPath: field.keyPath] = values[field.key].flatMap { Double($0) }
        }
        target.customMeasurements = custom
        target.notes = notes
        dismiss()
    }
}
