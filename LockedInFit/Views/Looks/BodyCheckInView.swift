import SwiftUI
import SwiftData
import UIKit

/// Optional, user-initiated body check-in. Saves a regular ProgressPhoto set
/// (keeping the existing progress-photo timeline intact) plus an
/// AppearanceCheckIn(kind: .body) scored from photos + composition data.
struct BodyCheckInView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \BodyFatEntry.date) private var bodyFats: [BodyFatEntry]
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }) private var completedWorkouts: [Workout]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]

    @State private var viewModel = AppearanceAnalysisViewModel()
    @State private var showSuggestionReview = false
    @State private var savedCheckIn = false

    private var settings: UserSettings? { settingsList.first }
    private var usesOpenRouter: Bool {
        KeychainService.openRouterAPIKey != nil
    }
    private var heightLooksDefault: Bool {
        let height = settings?.heightCm ?? 0
        return height <= 0 || height == 175 // matches the unedited UserSettings default
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    switch viewModel.phase {
                    case .analyzing:
                        DashboardCard(title: "Analyzing", systemImage: "sparkles") {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Scoring from photos, weight, body fat, and training history…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    case .reviewing:
                        reviewSection
                    default:
                        captureSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Body Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.snappy, value: viewModel.phase)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $showSuggestionReview, onDismiss: { dismiss() }) {
                NavigationStack { AppearanceSuggestionReviewView() }
            }
        }
    }

    // MARK: - Capture

    private var captureSection: some View {
        VStack(spacing: 14) {
            DashboardCard(title: "Private by Default", systemImage: "lock") {
                Text(usesOpenRouter
                     ? "Photos stay on your device and also save to your Progress Photos timeline. With OpenRouter enabled, they're additionally sent to your chosen model for optional observations; nothing is saved until you review."
                     : "Photos stay on your device and also save to your Progress Photos timeline. Analysis runs locally; nothing is saved until you review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DashboardCard(title: "Photos (Optional)", systemImage: "figure.stand") {
                VStack(spacing: 4) {
                    PhotoSlotPicker(label: "Front", image: $viewModel.frontImage)
                    PhotoSlotPicker(label: "Side", image: $viewModel.sideImage)
                    PhotoSlotPicker(label: "Back", image: $viewModel.backImage)
                }
                Text("Same spot, same lighting, relaxed posture. You can also score from composition data alone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            dataStatusCard

            Button {
                Task {
                    await viewModel.analyzeBody(inputs: scoreInputs, context: suggestionContext, useAI: usesOpenRouter)
                }
            } label: {
                Label("Analyze", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.bodyImages.isEmpty && weights.isEmpty)

            if viewModel.bodyImages.isEmpty && weights.isEmpty {
                Text("Add at least one photo or log a body weight first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dataStatusCard: some View {
        DashboardCard(title: "Data Being Used", systemImage: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 6) {
                dataRow(label: "Weight",
                        value: weights.last.map { Formatters.kg($0.weightKg) },
                        missingHint: "Log a weigh-in for composition scoring.")
                dataRow(label: "Body fat",
                        value: bodyFats.last.map { "\(Formatters.trimmed($0.bodyFatPercentage))%" },
                        missingHint: "Missing; score will be composition-limited with lower confidence.")
                dataRow(label: "Height",
                        value: heightLooksDefault ? nil : settings.map { "\(Formatters.trimmed($0.heightCm)) cm" },
                        missingHint: "Looks unset; update it in Settings → Profile for the lean-mass component.")
                dataRow(label: "Workouts (28d)",
                        value: "\(completedWorkouts.filter { $0.date > Date().daysAgo(28) }.count)",
                        missingHint: "")
            }
        }
    }

    private func dataRow(label: String, value: String?, missingHint: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.medium))
                .frame(width: 100, alignment: .leading)
            if let value {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(missingHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
    }

    // MARK: - Review

    @ViewBuilder
    private var reviewSection: some View {
        if let result = viewModel.bodyResult, let draft = viewModel.draftCheckIn {
            DashboardCard(title: "Body Score", systemImage: "figure.stand") {
                HStack(spacing: 16) {
                    ScoreRingView(label: "Today", score: draft.totalScore, maxScore: 100, color: .indigo)
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Confidence \(Formatters.percent(result.confidence))", systemImage: "gauge.medium")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if result.leannessGuard {
                            Label("Leanness is not the limiter: no cut advice given", systemImage: "shield.checkered")
                                .font(.caption2)
                                .foregroundStyle(.teal)
                        }
                    }
                    Spacer()
                }
            }

            DashboardCard(title: "Why This Score?", systemImage: "questionmark.circle") {
                VStack(spacing: 8) {
                    breakdownRow("Composition", result.composition, 40)
                    breakdownRow("Lean mass proxy", result.leanMass, 15)
                    breakdownRow("Training consistency", result.training, 15)
                    breakdownRow("Posture", result.posture, 15)
                    breakdownRow("Trend vs goal", result.trendDirection, 15)
                }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(result.explanations, id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").font(.caption).foregroundStyle(.tertiary)
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 6)
            }

            if result.compositionLimited || !result.confidenceNotes.isEmpty || (viewModel.aiResult?.isUnableToAssess ?? false) {
                DashboardCard(title: "Confidence & Tracking Notes", systemImage: "gauge.medium") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("These affect how much to trust the score above, not the score itself.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if viewModel.aiResult?.isUnableToAssess ?? false {
                            Text("AI couldn't assess this photo. The score above stands on its own; nothing was penalized for it.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        ForEach(result.confidenceNotes, id: \.self) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").font(.caption).foregroundStyle(.tertiary)
                                Text(line).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let ai = viewModel.aiResult, !ai.observations.isEmpty {
                DashboardCard(title: "AI Observations", systemImage: "sparkles") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(ai.observations, id: \.self) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").font(.caption).foregroundStyle(.tertiary)
                                Text(line).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("Via \(viewModel.providerUsed)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            DashboardCard(title: "Notes", systemImage: "note.text") {
                TextField("Optional: pump status, time of day…", text: $viewModel.notes, axis: .vertical)
                    .font(.subheadline)
            }

            VStack(spacing: 8) {
                Button { saveCheckIn() } label: {
                    Label("Save Check-In", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) { viewModel.phase = .intro } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func breakdownRow(_ label: String, _ value: Double, _ max: Double) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label).font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(max))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(value, max), total: max)
                .tint(value / max >= 0.7 ? .green : value / max >= 0.4 ? .orange : .red)
        }
    }

    // MARK: - Inputs / save

    private var scoreInputs: AppearanceScoringService.BodyScoreInputs {
        let (hitDays, trackedDays) = recentProteinAdherence
        return AppearanceScoringService.BodyScoreInputs(
            latestWeightKg: weights.last?.weightKg,
            latestBodyFatPercent: bodyFats.last?.bodyFatPercentage,
            heightCm: heightLooksDefault ? nil : settings?.heightCm,
            sex: settings?.sex ?? .male,
            goal: activeGoals.first,
            workouts: completedWorkouts,
            weights: weights,
            photoCount: viewModel.bodyImages.count,
            recentProteinHitDays: hitDays,
            recentProteinTrackedDays: trackedDays)
    }

    /// Days in the last 14 with a protein target hit, out of days with any
    /// meal logged: connects nutrition consistency into the body-score
    /// narrative. `nil`/`nil` when there's too little logged data to mean anything.
    private var recentProteinAdherence: (hit: Int?, tracked: Int?) {
        guard let target = activeGoals.first?.proteinTarget, target > 0 else { return (nil, nil) }
        let calendar = Calendar.current
        var hitDays = 0
        var trackedDays = 0
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let dayMeals = meals.filter { calendar.isDate($0.date, inSameDayAs: day) }
            guard !dayMeals.isEmpty else { continue }
            trackedDays += 1
            if dayMeals.reduce(0, { $0 + $1.protein }) >= target { hitDays += 1 }
        }
        guard trackedDays >= 3 else { return (nil, nil) }
        return (hitDays, trackedDays)
    }

    private var suggestionContext: SuggestionGenerationService.Context {
        let nutrition = DailyNutritionCalculator.summary(meals: meals)
        return SuggestionGenerationService.Context(
            settings: settings,
            goal: activeGoals.first,
            todaySodiumMg: nutrition.sodium,
            sodiumLimitMg: max(1, settings?.sodiumLimitMg ?? 2300),
            recentWorkoutCount: completedWorkouts.filter { $0.date > Date().daysAgo(28) }.count)
    }

    private func saveCheckIn() {
        guard !savedCheckIn, let checkIn = viewModel.save(into: context) else { return }
        savedCheckIn = true
        // Mirror into the existing Progress Photos timeline when photos exist.
        // Files are saved separately so deleting one record never orphans the other.
        if !viewModel.bodyImages.isEmpty {
            let progressPhoto = ProgressPhoto(
                date: checkIn.date,
                frontPhotoPath: viewModel.frontImage.flatMap { ImageStore.save($0, prefix: "front") },
                sidePhotoPath: viewModel.sideImage.flatMap { ImageStore.save($0, prefix: "side") },
                backPhotoPath: viewModel.backImage.flatMap { ImageStore.save($0, prefix: "back") },
                notes: "Body check-in · score \(Int(checkIn.totalScore))/100")
            context.insert(progressPhoto)
        }
        if viewModel.insertedSuggestionCount == 0 {
            dismiss()
        } else {
            showSuggestionReview = true
        }
    }
}
