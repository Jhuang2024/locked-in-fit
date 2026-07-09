import SwiftUI
import UIKit

// MARK: - Keyboard dismissal

/// Numeric keypads (.decimalPad/.numberPad) have no built-in return key, so
/// without this the keyboard has no way to close. Adds a "Done" button above
/// the keyboard that resigns first responder.
extension View {
    func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Design tokens

enum CardMetrics {
    static let cornerRadius: CGFloat = 18
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 14
}

/// Consistent card chrome used across every card in the app: soft fill,
/// a hairline border for definition in both appearances, no heavy shadow.
struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CardMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}

// MARK: - Press feedback

/// Subtle scale + fade feedback for tappable rows and buttons, so interactions
/// feel responsive instead of just flat-flipping between two static states.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Brand

struct AppBrandMark: View {
    let size: CGFloat

    var body: some View {
        Image("AppMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}

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
                    .tracking(0.3)
                    .textCase(.uppercase)
                Spacer()
            }
            content
        }
        .padding(CardMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
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
                    .stroke(color.opacity(0.16), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
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
            .frame(width: 60, height: 60)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ScoreRingView

/// A big "N / max" circular gauge, e.g. a health score or satiety score out of 100.
struct ScoreRingView: View {
    let label: String
    let score: Double
    let maxScore: Double
    let color: Color

    private var progress: Double { maxScore > 0 ? max(0, min(1, score / maxScore)) : 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(score.rounded()))")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("/\(Int(maxScore))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            Text(label)
                .font(.caption.weight(.medium))
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
        .padding(CardMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

// MARK: - EmptyStateView

/// A quiet, non-demo empty state: an outlined glyph, a short title, and one line
/// of guidance. No illustrations, no sample data; just what to do next.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
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
        .cardBackground()
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
        .cardBackground()
    }
}

// MARK: - Stat chip

struct StatChip: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - SleepTimesTable

/// Two-row table of average bedtime/wake time (see
/// SleepScoringService.averageTimes), shared by the Today dashboard, the
/// Sleep page, and Sleep Trends so all three read the same values the same
/// way. Missing values show as "N/A" rather than hiding the row, so the
/// table's shape doesn't shift as data fills in.
struct SleepTimesTable: View {
    let bedtime: String?
    let wake: String?

    var body: some View {
        VStack(spacing: 0) {
            row(label: "Avg Bedtime", value: bedtime, icon: "moon.fill")
            Divider().padding(.leading, 30)
            row(label: "Avg Wake Time", value: wake, icon: "sun.max.fill")
        }
    }

    private func row(label: String, value: String?, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value ?? "N/A")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(value == nil ? .secondary : .primary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - SectionLabel

/// Small caps section label for use above groups of cards or list sections,
/// matching the DashboardCard header treatment for a consistent hierarchy.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.3)
            .textCase(.uppercase)
    }
}
