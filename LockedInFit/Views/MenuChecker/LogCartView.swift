import SwiftUI
import SwiftData
import PhotosUI

/// The "Log This Meal" flow. Classifies the cart as breakfast/lunch/dinner/snack,
/// lets the user set date/time, name, notes, portion eaten, save-as-reusable, and
/// a photo, then logs the whole cart into the normal food history. Double taps
/// can't create two meals — the button disables and the logger de-duplicates.
struct LogCartView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    let lines: [CartLine]
    let summary: CartSummary
    let onLogged: () -> Void

    @State private var mealType: MealType = .guess()
    @State private var date = Date()
    @State private var mealName = ""
    @State private var notes = ""
    @State private var ateFull = true
    @State private var portionPercent = 100.0
    @State private var saveReusable = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPath: String?
    @State private var isLogging = false
    @State private var didLog = false

    private var settings: UserSettings? { settingsList.first }
    private var effectiveNutrition: ResolvedNutrition {
        summary.nutrition * (ateFull ? 1 : portionPercent / 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Date & time", selection: $date)
                } header: {
                    Text("Classify")
                } footer: {
                    Text("Defaults to now — change the date to log a past meal.")
                }

                Section("Totals to log") {
                    MacroReadout(nutrition: effectiveNutrition).padding(.vertical, 4)
                    HStack {
                        HealthChip(score: summary.combinedHealthScore)
                        SatietyChip(score: summary.combinedSatietyScore)
                        Spacer()
                        Text("\(summary.itemCount) items").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("How much did you eat?") {
                    Toggle("Ate the full amount", isOn: $ateFull)
                    if !ateFull {
                        VStack(alignment: .leading) {
                            Text("Ate \(Int(portionPercent))%")
                            Slider(value: $portionPercent, in: 10...100, step: 5)
                        }
                    }
                }

                Section("Details") {
                    TextField("Meal name (optional)", text: $mealName)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                    Toggle("Save as reusable meal", isOn: $saveReusable)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoPath == nil ? "Add meal photo" : "Photo added", systemImage: photoPath == nil ? "camera" : "checkmark.circle.fill")
                    }
                }

                ForEach(summary.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
            }
            .navigationTitle("Log This Meal")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isLogging ? "Logging…" : "Log") { logMeal() }
                        .disabled(isLogging || didLog || lines.isEmpty)
                        .fontWeight(.bold)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        photoPath = ImageStore.save(image, prefix: "meal")
    }

    private func logMeal() {
        guard !isLogging, !didLog else { return } // guard against double taps
        isLogging = true
        let options = MealCartLogger.Options(
            mealType: mealType, date: date, mealName: mealName, notes: notes,
            ateFullAmount: ateFull, portionPercent: portionPercent,
            saveAsReusableMeal: saveReusable, photoPath: photoPath)
        let result = MealCartLogger.log(lines: lines, options: options, settings: settings, context: context)
        isLogging = false
        switch result {
        case .logged:
            didLog = true
            MealCartLogger.clearCart(lines, context: context)
            onLogged()
            dismiss()
        case .duplicateIgnored:
            // Already logged moments ago; make sure the cart is cleared and leave.
            didLog = true
            MealCartLogger.clearCart(lines, context: context)
            onLogged()
            dismiss()
        case .emptyCart:
            dismiss()
        }
    }
}
