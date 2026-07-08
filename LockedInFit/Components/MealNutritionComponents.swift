import SwiftUI
import SwiftData

/// Shared status tiers for health/satiety scores across the food log.
enum MealScoreTier {
    case strong, decent, mixed, poor

    init(_ score: Double) {
        switch score {
        case 80...: self = .strong
        case 60..<80: self = .decent
        case 40..<60: self = .mixed
        default: self = .poor
        }
    }

    var color: Color {
        switch self {
        case .strong: return .green
        case .decent: return .teal
        case .mixed: return .orange
        case .poor: return .red
        }
    }
}

/// Compact "72 Health" pill for the food log list, small enough for two per
/// row without crowding the card.
struct MealScoreChip: View {
    let label: String
    let score: Double

    var body: some View {
        let color = MealScoreTier(score).color
        VStack(spacing: 1) {
            Text("\(Int(score.rounded()))")
                .font(.system(.footnote, design: .rounded, weight: .bold))
            Text(label)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(color)
        .frame(width: 40)
        .padding(.vertical, 5)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Facts/concerns list shared between the food log's expandable row and
/// MealDetailView, so both stay visually consistent.
struct MealFactsConcernsView: View {
    let facts: [String]
    let concerns: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(facts, id: \.self) { fact in
                Label(fact, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(concerns, id: \.self) { concern in
                concernRow(concern)
            }
        }
    }

    private func concernRow(_ concern: String) -> some View {
        let isReassurance = concern.hasPrefix("No major concerns")
        let icon = isReassurance ? "checkmark.seal" : "exclamationmark.triangle"
        let color: Color = isReassurance ? .secondary : .orange
        return Label(concern, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }
}

/// Health/satiety scores + summary + expandable facts/concerns for a logged
/// meal, or an analyzing/unavailable/not-analyzed state with a manual
/// "Analyze" retry. Shared between the food log list and MealDetailView.
struct MealNutritionAnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var meal: MealLog
    var settings: UserSettings?

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch meal.analysisState {
            case .completed:
                completedRow
                if expanded {
                    MealFactsConcernsView(facts: meal.facts, concerns: meal.concerns)
                        .padding(.leading, 2)
                }
            case .analyzing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Analyzing nutrition…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed:
                statusRow(text: meal.analysisSummary.isEmpty ? "AI meal analysis unavailable." : meal.analysisSummary)
            case .notAnalyzed:
                statusRow(text: "Not analyzed")
            }
        }
    }

    private var completedRow: some View {
        HStack(alignment: .top, spacing: 10) {
            MealScoreChip(label: "Health", score: meal.healthScore)
            MealScoreChip(label: "Satiety", score: meal.satietyScore)
            VStack(alignment: .leading, spacing: 3) {
                if !meal.analysisSummary.isEmpty {
                    Text(meal.analysisSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !meal.facts.isEmpty || !meal.concerns.isEmpty {
                    Button {
                        withAnimation(.snappy) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Text(expanded ? "Hide details" : "Facts & concerns")
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func statusRow(text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task {
                    await MealNutritionAnalysisRunner.analyze(meal: meal, settings: settings, context: modelContext)
                }
            } label: {
                Label("Analyze", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
    }
}
