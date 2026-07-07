import SwiftUI
import SwiftData
import UIKit

/// Hub for the appearance system: latest scores, streak, pending suggestions,
/// and entry points into every Looks flow.
struct LooksDashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AppearanceCheckIn.date, order: .reverse) private var checkIns: [AppearanceCheckIn]
    @Query private var suggestions: [AppearanceSuggestion]
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \BodyFatEntry.date) private var bodyFats: [BodyFatEntry]
    @Query(filter: #Predicate<Workout> { $0.completed && !$0.isTemplate }) private var completedWorkouts: [Workout]

    @State private var showFaceCheckIn = false
    @State private var showBodyCheckIn = false

    private var faceCheckIns: [AppearanceCheckIn] { checkIns.filter { $0.kind == .face } }
    private var bodyCheckIns: [AppearanceCheckIn] { checkIns.filter { $0.kind == .body } }
    private var latestFace: AppearanceCheckIn? { faceCheckIns.first }
    private var latestBody: AppearanceCheckIn? { bodyCheckIns.first }
    /// Composition-only fallback so a body score exists even with no body photo check-in.
    private var liveBodyScore: AppearanceScoringService.BodyScoreResult? {
        AppearanceScoringService.liveBodyScore(
            weights: weights, bodyFats: bodyFats, workouts: completedWorkouts,
            settings: settingsList.first, goal: activeGoals.first)
    }
    private var effectiveBodyScore: Double? {
        AppearanceScoringService.effectiveBodyScore(checkIn: latestBody, live: liveBodyScore)
    }
    /// Same formula the Dashboard widget uses, so the two never disagree.
    private var combined: Double? {
        AppearanceScoringService.combinedScore(face: latestFace, body: latestBody, liveBody: liveBodyScore)
    }
    private var streak: Int { AppearanceScoringService.faceStreak(history: checkIns) }
    private var pendingCount: Int { suggestions.filter { $0.status == .pending }.count }
    private var activeCount: Int { suggestions.filter { $0.status == .approved }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                scoresCard
                statsCard
                actionButtons
                if checkIns.isEmpty {
                    explainerCard
                } else {
                    recentCheckInsCard
                }
                privacyFootnote
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Looks")
        .sheet(isPresented: $showFaceCheckIn) { FaceCheckInSheet() }
        .sheet(isPresented: $showBodyCheckIn) { BodyCheckInView() }
    }

    private var scoresCard: some View {
        DashboardCard(title: "Appearance Scores", systemImage: "sparkles") {
            HStack {
                faceRing
                Spacer()
                bodyRing
                Spacer()
                ScoreRingView(label: "Combined", score: combined ?? 0, maxScore: 100,
                              color: combined == nil ? .gray : .teal)
            }
            Text("Scores track consistency, logged grooming/sleep habits, composition data, and comparison against your own history — never photo quality, and never attractiveness or anyone else's standard.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            if latestFace != nil || effectiveBodyScore != nil {
                Text("Tap a score for its breakdown.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var faceRing: some View {
        let ring = ScoreRingView(label: "Face", score: latestFace?.totalScore ?? 0, maxScore: 100,
                                  color: latestFace == nil ? .gray : .accentColor)
        if let latestFace {
            NavigationLink(destination: AppearanceCheckInDetailView(checkIn: latestFace)) { ring }
                .buttonStyle(.pressable)
        } else {
            ring
        }
    }

    @ViewBuilder
    private var bodyRing: some View {
        let ring = ScoreRingView(label: "Body", score: effectiveBodyScore ?? 0, maxScore: 100,
                                  color: effectiveBodyScore == nil ? .gray : .indigo)
        if let latestBody {
            NavigationLink(destination: AppearanceCheckInDetailView(checkIn: latestBody)) { ring }
                .buttonStyle(.pressable)
        } else if let liveBodyScore {
            NavigationLink(destination: LiveBodyScoreDetailView(result: liveBodyScore)) { ring }
                .buttonStyle(.pressable)
        } else {
            ring
        }
    }

    private var statsCard: some View {
        DashboardCard(title: "Status", systemImage: "chart.bar") {
            HStack {
                StatChip(label: "Face streak", value: streak > 0 ? "\(streak)d" : "N/A")
                StatChip(label: "Last face", value: latestFace.map { Formatters.shortDate($0.date) } ?? "None")
                StatChip(label: "Last body", value: latestBody.map { Formatters.shortDate($0.date) } ?? (liveBodyScore != nil ? "Estimated" : "None"))
            }
            HStack {
                StatChip(label: "Pending suggestions", value: "\(pendingCount)", color: pendingCount > 0 ? .orange : .primary)
                StatChip(label: "Active actions", value: "\(activeCount)")
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { showFaceCheckIn = true } label: {
                    Label("Take Face Photo", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                Button { showBodyCheckIn = true } label: {
                    Label("Upload Body Photos", systemImage: "figure.stand")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
            HStack(spacing: 8) {
                NavigationLink(destination: AppearanceSuggestionReviewView()) {
                    Label(pendingCount > 0 ? "Review Suggestions (\(pendingCount))" : "Review Suggestions",
                          systemImage: "lightbulb")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                NavigationLink(destination: AppearanceTrendsView()) {
                    Label("Appearance Trends", systemImage: "chart.xyaxis.line")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var explainerCard: some View {
        DashboardCard(title: "How it works", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                explainerRow(icon: "camera", text: "Daily face photos build a personal baseline. Same lighting, same angle, no filters.")
                explainerRow(icon: "figure.stand", text: "Body check-ins are optional and user-initiated; a body score exists from your weight and body fat alone, and photos add the visual component.")
                explainerRow(icon: "lightbulb", text: "Each check-in generates a few specific suggestions. Nothing becomes a task until you approve it.")
                explainerRow(icon: "lock", text: "Photos stay on this device. AI analysis only runs if you've enabled it in AI settings, and you review results before saving.")
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

    private var recentCheckInsCard: some View {
        DashboardCard(title: "Recent Check-Ins", systemImage: "clock.arrow.circlepath") {
            VStack(spacing: 10) {
                ForEach(checkIns.prefix(8), id: \.persistentModelID) { checkIn in
                    NavigationLink(destination: AppearanceCheckInDetailView(checkIn: checkIn)) {
                        checkInRow(checkIn)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        Button(role: .destructive) { delete(checkIn) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func checkInRow(_ checkIn: AppearanceCheckIn) -> some View {
        HStack(spacing: 12) {
            if let image = ImageStore.load(checkIn.photoPath ?? checkIn.frontPhotoPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: checkIn.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(checkIn.kind.label) check-in")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(Formatters.mediumDate(checkIn.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(checkIn.totalScore))")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Text("/100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacyFootnote: some View {
        Text("Photos are stored on-device only. Delete everything anytime in Settings → Looks & Calendar.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private func delete(_ checkIn: AppearanceCheckIn) {
        ImageStore.deleteAll(checkIn.allPhotoPaths)
        context.delete(checkIn)
    }
}

/// Sheet wrapper so FaceCheckInView also works when pushed via NavigationLink
/// (e.g. from the Today checklist).
struct FaceCheckInSheet: View {
    var body: some View {
        NavigationStack { FaceCheckInView() }
    }
}

// MARK: - Check-in detail

struct AppearanceCheckInDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let checkIn: AppearanceCheckIn

    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DashboardCard(title: "\(checkIn.kind.label) Score", systemImage: checkIn.kind.systemImage) {
                    HStack(spacing: 16) {
                        ScoreRingView(label: Formatters.mediumDate(checkIn.date),
                                      score: checkIn.totalScore, maxScore: 100,
                                      color: checkIn.kind == .face ? .accentColor : .indigo)
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Confidence \(Formatters.percent(checkIn.confidence))", systemImage: "gauge.medium")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if checkIn.confidence < 0.5 {
                                Text("Low confidence — more check-ins or logged data sharpens this.")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                    }
                }

                photosCard

                DashboardCard(title: "Score Breakdown", systemImage: "list.bullet.rectangle") {
                    VStack(spacing: 8) {
                        if checkIn.kind == .face {
                            breakdownRow("Skin", checkIn.skinScore, 25)
                            breakdownRow("Symmetry", checkIn.symmetryScore, 20)
                            breakdownRow("Grooming", checkIn.groomingScore, 20)
                            breakdownRow("Puffiness vs baseline", checkIn.puffinessScore, 20)
                            breakdownRow("Consistency", checkIn.trendScore, 15)
                        } else {
                            breakdownRow("Composition", checkIn.compositionScore, 40)
                            breakdownRow("Lean mass proxy", checkIn.muscularityScore, 15)
                            breakdownRow("Photo coverage", checkIn.postureScore, 15)
                            breakdownRow("Trend vs goal", checkIn.trendScore, 15)
                        }
                    }
                }

                if !checkIn.notes.isEmpty {
                    DashboardCard(title: "Notes", systemImage: "note.text") {
                        Text(checkIn.notes)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(checkIn.kind.label) Check-In")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
        }
        .confirmationDialog("Delete this check-in and its photos?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                ImageStore.deleteAll(checkIn.allPhotoPaths)
                context.delete(checkIn)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var photosCard: some View {
        let images: [(String, UIImage)] = [
            ("Photo", checkIn.photoPath), ("Front", checkIn.frontPhotoPath),
            ("Side", checkIn.sidePhotoPath), ("Back", checkIn.backPhotoPath)
        ].compactMap { label, path in
            ImageStore.load(path).map { (label, $0) }
        }
        if !images.isEmpty {
            DashboardCard(title: "Photos", systemImage: "photo") {
                HStack(spacing: 8) {
                    ForEach(images, id: \.0) { label, image in
                        VStack(spacing: 4) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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

// MARK: - Live (composition-only) body score detail

/// Breakdown for a body score computed from composition data alone, with no
/// saved check-in yet. Formatted like AppearanceCheckInDetailView so the two
/// read the same way regardless of which one produced the score.
struct LiveBodyScoreDetailView: View {
    let result: AppearanceScoringService.BodyScoreResult

    @State private var showBodyCheckIn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DashboardCard(title: "Body Score", systemImage: "figure.stand") {
                    HStack(spacing: 16) {
                        ScoreRingView(label: "Estimated", score: result.total, maxScore: 100, color: .indigo)
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Confidence \(Formatters.percent(result.confidence))", systemImage: "gauge.medium")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if result.compositionLimited {
                                Label("Composition-limited", systemImage: "exclamationmark.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            if result.leannessGuard {
                                Label("Leanness is not the limiter; no cut advice given", systemImage: "shield.checkered")
                                    .font(.caption2)
                                    .foregroundStyle(.teal)
                            }
                        }
                        Spacer()
                    }
                    Text("No body photo check-in yet. This score is estimated from your logged weight and body fat.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                DashboardCard(title: "Score Breakdown", systemImage: "list.bullet.rectangle") {
                    VStack(spacing: 8) {
                        breakdownRow("Composition", result.composition, 40)
                        breakdownRow("Lean mass proxy", result.leanMass, 15)
                        breakdownRow("Training consistency", result.training, 15)
                        breakdownRow("Photo coverage", result.photoPosture, 15)
                        breakdownRow("Trend vs goal", result.trendDirection, 15)
                    }
                }

                DashboardCard(title: "Why This Score?", systemImage: "questionmark.circle") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(result.explanations, id: \.self) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").font(.caption).foregroundStyle(.tertiary)
                                Text(line).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Button { showBodyCheckIn = true } label: {
                    Label("Add Body Photos", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Body Score")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showBodyCheckIn) { BodyCheckInView() }
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
