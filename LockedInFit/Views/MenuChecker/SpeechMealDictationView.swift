import SwiftUI

/// Speech-driven meal capture: describe a meal out loud, review the parsed foods,
/// correct anything, and confirm. Deliberately never logs on its own: it hands
/// an editable preview back to the caller (the manual Add Meal flow), which stays
/// fully usable by typing. Applies the same oil rules as Menu Checker.
struct SpeechMealDictationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dictation = SpeechDictationController()

    /// Called with the reviewed entries and the detected meal type on confirm.
    let onConfirm: ([ParsedMealEntry], MealType) -> Void

    @State private var transcript = ""
    @State private var preview: ParsedMealPreview?
    @State private var mealType: MealType = .guess()

    private var total: ResolvedNutrition {
        (preview?.entries ?? []).reduce(.zero) { $0 + $1.nutrition }
    }

    var body: some View {
        NavigationStack {
            Form {
                micSection
                if let preview, !preview.isEmpty {
                    previewSection(preview)
                    totalsSection
                } else if !transcript.isEmpty {
                    Section {
                        Text("Tap Parse to turn your description into foods.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Speak Your Meal")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dictation.reset(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onConfirm(preview?.entries.filter { !$0.isUncertain && $0.nutrition.calories > 0 } ?? [], mealType)
                        dismiss()
                    }
                    .disabled((preview?.entries.contains { !$0.isUncertain && $0.nutrition.calories > 0 }) != true)
                    .fontWeight(.bold)
                }
            }
            .onChange(of: dictation.transcript) { _, new in
                if !new.isEmpty { transcript = new }
            }
        }
    }

    private var micSection: some View {
        Section {
            VStack(spacing: 12) {
                Button {
                    Task {
                        if dictation.isListening { dictation.stop(); parse() }
                        else { await dictation.start() }
                    }
                } label: {
                    ZStack {
                        Circle().fill(dictation.isListening ? Color.red : Color.accentColor).frame(width: 74, height: 74)
                        Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 28)).foregroundStyle(.white)
                    }
                    .overlay(alignment: .bottom) {
                        if dictation.isListening {
                            Text("Listening…").font(.caption2).foregroundStyle(.red).offset(y: 18)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                stateFootnote

                TextField("Or type: “two eggs, toast with butter, a banana”", text: $transcript, axis: .vertical)
                    .lineLimit(2...5)
                Button("Parse meal") { parse() }
                    .disabled(transcript.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(maxWidth: .infinity)
        } footer: {
            Text("Understands quantities and prep like “half”, “a little butter”, “steamed”, “raw”, “grilled”. Steamed and raw foods get zero added oil.")
        }
    }

    @ViewBuilder private var stateFootnote: some View {
        switch dictation.state {
        case .denied:
            Text("Microphone or speech permission is off. You can still type your meal below.")
                .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
        case .unavailable:
            Text("Speech recognition isn't available right now. Type your meal below.")
                .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
        case .error(let msg):
            Text(msg).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
        default:
            EmptyView()
        }
    }

    private func previewSection(_ preview: ParsedMealPreview) -> some View {
        Section {
            ForEach(previewEntries) { $entry in
                ParsedEntryRow(entry: $entry)
            }
            .onDelete { offsets in
                self.preview?.entries.remove(atOffsets: offsets)
            }
        } header: {
            HStack {
                Text("Parsed foods")
                Spacer()
                Text("Confidence \(preview.confidence.label.lowercased())").font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            if !preview.mentionedBrands.isEmpty {
                Text("Mentioned: \(preview.mentionedBrands.joined(separator: ", "))")
            }
            if !preview.uncertainTerms.isEmpty {
                Text("Flagged as uncertain; tap to set nutrition or delete: \(preview.uncertainTerms.joined(separator: ", "))")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var totalsSection: some View {
        Section("Total") {
            Picker("Meal", selection: $mealType) { ForEach(MealType.allCases) { Text($0.label).tag($0) } }
            MacroReadout(nutrition: total).padding(.vertical, 4)
        }
    }

    // Binding into the preview's entries for per-row editing.
    private var previewEntries: Binding<[ParsedMealEntry]> {
        Binding(get: { preview?.entries ?? [] }, set: { preview?.entries = $0 })
    }

    private func parse() {
        let result = MealSpeechParser.parse(transcript)
        mealType = result.mealType
        // Keep uncertain rows so the user can fix them, but they won't be added
        // unless given nutrition.
        preview = result
    }
}

/// Editable row for one parsed food: name + macros, correctable before adding.
struct ParsedEntryRow: View {
    @Binding var entry: ParsedMealEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if entry.isUncertain {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                }
                TextField("Food", text: $entry.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(entry.nutrition.calories)) kcal").font(.subheadline.weight(.bold))
                Button { withAnimation { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if !entry.note.isEmpty {
                Text(entry.note).font(.caption2).foregroundStyle(.secondary)
            }
            if expanded {
                macroField("Calories", value: $entry.nutrition.calories)
                macroField("Protein", value: $entry.nutrition.protein)
                macroField("Carbs", value: $entry.nutrition.carbs)
                macroField("Fat", value: $entry.nutrition.fat)
            }
        }
    }

    private func macroField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
        }
    }
}
