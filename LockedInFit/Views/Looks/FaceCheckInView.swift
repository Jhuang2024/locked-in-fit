import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Daily face check-in: privacy note → photo → Vision validation → local
/// scoring (+ optional AI) → reviewable result → save → suggestion review.
struct FaceCheckInView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]
    @Query(sort: \AppearanceCheckIn.date, order: .reverse) private var checkIns: [AppearanceCheckIn]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }) private var completedWorkouts: [Workout]
    @Query private var checklistItems: [DailyChecklistItem]
    @Query(sort: \SleepLog.date, order: .reverse) private var sleepLogs: [SleepLog]

    @State private var viewModel = AppearanceAnalysisViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showSuggestionReview = false

    private var settings: UserSettings? { settingsList.first }
    private var usesOpenRouter: Bool {
        AIMode(rawValue: settings?.aiModeRaw ?? "mock") == .openRouter && KeychainService.openRouterAPIKey != nil
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

    /// Connects the score to actually-logged grooming/sleep behavior instead
    /// of photo statistics.
    private var looksComplianceRatio: Double? {
        DailyChecklistService.recentComplianceRatio(checklistItems, category: .looks)
    }
    /// Prefers real logged sleep quality (SleepLog score) once the user is
    /// using sleep tracking; falls back to the sleep-category checklist proxy
    /// for anyone who isn't, so the connection is never silently ignored.
    private var sleepComplianceRatio: Double? {
        let recentLogs = sleepLogs.filter { $0.date > Date().daysAgo(14) }
        if !recentLogs.isEmpty {
            let goodNights = recentLogs.filter { $0.totalScore >= 70 }.count
            return Double(goodNights) / Double(recentLogs.count)
        }
        return DailyChecklistService.recentComplianceRatio(checklistItems, category: .sleep)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                switch viewModel.phase {
                case .intro, .pickingPhoto, .blocked, .validating:
                    captureSection
                case .analyzing:
                    analyzingCard
                case .reviewing:
                    reviewSection
                case .failed(let message):
                    failedCard(message)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Face Check-In")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: viewModel.phase)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                viewModel.faceImage = image
                Task { await viewModel.validateFacePhoto() }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) {
            Task {
                if let data = try? await pickerItem?.loadTransferable(type: Data.self),
                   let image = UIImage.downsampled(from: data, maxDimension: 1600) {
                    viewModel.faceImage = image
                    await viewModel.validateFacePhoto()
                }
            }
        }
        .sheet(isPresented: $showSuggestionReview, onDismiss: { dismiss() }) {
            NavigationStack { AppearanceSuggestionReviewView() }
        }
    }

    // MARK: - Capture

    private var captureSection: some View {
        VStack(spacing: 14) {
            privacyCard
            guidanceCard
            photoCard
            if viewModel.phase == .validating {
                DashboardCard(title: "Checking Photo", systemImage: "viewfinder") {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking face detection, sharpness, and exposure…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let validation = viewModel.validation {
                validationCard(validation)
            }
            analyzeButton
        }
    }

    private var privacyCard: some View {
        DashboardCard(title: "Private by Default", systemImage: "lock") {
            Text(usesOpenRouter
                 ? "This photo is stored on your device. Because OpenRouter analysis is enabled in AI settings, the photo will also be sent to your chosen model for optional observations; nothing is saved until you review the result."
                 : "This photo is stored on your device only and analyzed locally. Nothing is saved until you review the result.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var guidanceCard: some View {
        DashboardCard(title: "Photo Guidance", systemImage: "camera.viewfinder") {
            VStack(alignment: .leading, spacing: 5) {
                guidanceRow("Front-facing, neutral expression")
                guidanceRow("Same lighting as previous photos when possible")
                guidanceRow("No filters, face centered, hair visible")
                guidanceRow("Avoid extreme angles")
            }
        }
    }

    private func guidanceRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var photoCard: some View {
        DashboardCard(title: "Today's Photo", systemImage: "camera") {
            VStack(spacing: 12) {
                if let image = viewModel.faceImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                HStack(spacing: 8) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            Label(viewModel.faceImage == nil ? "Take Photo" : "Retake", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func validationCard(_ validation: FacePhotoValidation) -> some View {
        DashboardCard(title: "Photo Check", systemImage: validation.isUsable ? "checkmark.seal" : "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 6) {
                if validation.issues.isEmpty {
                    Label("Looks good: one face, sharp, well exposed.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                ForEach(validation.blockers) { issue in
                    Label(issue.message, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                ForEach(validation.warnings) { issue in
                    Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var analyzeButton: some View {
        if let validation = viewModel.validation, viewModel.faceImage != nil {
            Button {
                Task {
                    await viewModel.analyzeFace(history: Array(checkIns),
                                                context: suggestionContext,
                                                useAI: usesOpenRouter,
                                                looksComplianceRatio: looksComplianceRatio,
                                                sleepComplianceRatio: sleepComplianceRatio)
                }
            } label: {
                Label(validation.isUsable ? "Analyze Photo" : "Fix Issues Above First",
                      systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!validation.isUsable)
        }
    }

    private var analyzingCard: some View {
        DashboardCard(title: "Analyzing", systemImage: "sparkles") {
            HStack(spacing: 10) {
                ProgressView()
                Text(usesOpenRouter
                     ? "Scoring locally and requesting observations from \(settings?.aiModelName ?? "your model")…"
                     : "Scoring locally…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Review

    @ViewBuilder
    private var reviewSection: some View {
        if let result = viewModel.faceResult, let draft = viewModel.draftCheckIn {
            DashboardCard(title: "Face Score", systemImage: "face.smiling") {
                HStack(spacing: 16) {
                    ScoreRingView(label: "Today", score: draft.totalScore, maxScore: 100, color: .accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Confidence \(Formatters.percent(result.confidence))", systemImage: "gauge.medium")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let ai = viewModel.aiResult, ai.clampedAdjustment != 0 {
                            Text("Includes a \(ai.clampedAdjustment > 0 ? "+" : "")\(Int(ai.clampedAdjustment)) AI adjustment (\(viewModel.providerUsed)).")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }

            DashboardCard(title: "Why This Score?", systemImage: "questionmark.circle") {
                VStack(spacing: 8) {
                    reviewBreakdownRow("Skin", result.skin, 30)
                    reviewBreakdownRow("Symmetry", result.symmetry, 15)
                    reviewBreakdownRow("Grooming", result.grooming, 25)
                    reviewBreakdownRow("Puffiness vs baseline", result.puffiness, 30)
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

            if !result.confidenceNotes.isEmpty || result.confidence < 0.5 || (viewModel.aiResult?.isUnableToAssess ?? false) {
                DashboardCard(title: "Confidence & Tracking Notes", systemImage: "gauge.medium") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("These affect how much to trust the score above, not the score itself.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if result.confidence < 0.5 {
                            Text("Low confidence: more check-ins, logged grooming/sleep habits, or enabling AI analysis all sharpen this.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
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
                TextField("Optional: sleep, sodium, context…", text: $viewModel.notes, axis: .vertical)
                    .font(.subheadline)
            }

            if !viewModel.draftSuggestions.isEmpty {
                DashboardCard(title: "Suggestions Ready", systemImage: "lightbulb") {
                    Text("\(viewModel.draftSuggestions.count) suggestions were generated from this check-in. Any that are genuinely new are ready to review after saving. Duplicates of ones you already have are merged automatically, and nothing becomes a task without your OK.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                Button { saveCheckIn() } label: {
                    Label("Save Check-In", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) { discard() } label: {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func reviewBreakdownRow(_ label: String, _ value: Double, _ max: Double) -> some View {
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

    private func failedCard(_ message: String) -> some View {
        DashboardCard(title: "Analysis Failed", systemImage: "exclamationmark.triangle") {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try Again") { viewModel.phase = .pickingPhoto }
                .buttonStyle(.bordered)
        }
    }

    private func saveCheckIn() {
        guard viewModel.save(into: context) != nil else { return }
        // Today's photo is done; pull today's pending face reminder.
        if let settings {
            Task {
                await NotificationService.refreshFaceReminders(
                    enabled: settings.faceReminderEnabled,
                    hour: settings.faceReminderHour,
                    minute: settings.faceReminderMinute,
                    faceCheckedInToday: true)
            }
        }
        if viewModel.insertedSuggestionCount == 0 {
            dismiss()
        } else {
            showSuggestionReview = true
        }
    }

    private func discard() {
        viewModel.faceImage = nil
        viewModel.validation = nil
        viewModel.draftCheckIn = nil
        viewModel.draftSuggestions = []
        viewModel.aiResult = nil
        viewModel.phase = .intro
    }
}
