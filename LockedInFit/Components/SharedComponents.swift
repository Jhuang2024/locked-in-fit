import SwiftUI

// MARK: - DashboardCard

struct DashboardCard<Content: View>: View {
    let title: String
    var systemImage: String?
    let content: Content

    init(title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - MacroRingView

struct MacroRingView: View {
    let label: String
    let current: Double
    let target: Double
    let unit: String
    let color: Color

    private var progress: Double { target > 0 ? min(1.2, current / target) : 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(current))")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }
            .frame(width: 64, height: 64)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ChartCard

struct ChartCard<Content: View>: View {
    let title: String
    var subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
                .frame(height: 180)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - EmptyStateView

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

// MARK: - StrengthScoreCard

struct StrengthScoreCard: View {
    let score: StrengthScore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: score.movement.systemImage)
                    .foregroundStyle(.tint)
                Text(score.movement.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if abs(score.trend) >= 1 {
                    Label("\(score.trend > 0 ? "+" : "")\(Int(score.trend))",
                          systemImage: score.trend > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(score.trend > 0 ? .green : .orange)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(score.score))")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("/ 1000")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(score.score, 1000), total: 1000)
                .tint(levelColor)
            HStack {
                Text(score.levelName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(levelColor)
                Spacer()
                if score.estimated1RM > 0 {
                    Text("e1RM \(Int(score.estimated1RM)) kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var levelColor: Color {
        switch score.score {
        case ..<150: return .gray
        case ..<300: return .teal
        case ..<450: return .blue
        case ..<600: return .indigo
        case ..<750: return .purple
        case ..<900: return .orange
        default: return .yellow
        }
    }
}

// MARK: - GoalProgressCard

struct GoalProgressCard: View {
    let title: String
    let current: String
    let target: String
    /// 0–1
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(current)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text("→ \(target)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: max(0, min(1, progress)))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Stat chip

struct StatChip: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
