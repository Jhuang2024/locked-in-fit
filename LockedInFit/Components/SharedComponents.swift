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

/// A small palette built from the app's one AccentColor (see
/// Assets.xcassets/AccentColor) instead of reaching for whatever system hue
/// is nearby. Anywhere a UI element needs a *progression* (a tier, a level,
/// "how far along") should use `tone(_:of:)` rather than stringing together
/// unrelated system colors (gray → teal → blue → indigo → purple → orange
/// is six unconnected hues with no visual relationship to each other or to
/// the app); a single hue that deepens as it climbs reads as one deliberate
/// scale. `elite` is the one deliberate break from that rule, reserved for
/// the single top tier: the "you made it" color premium apps use once,
/// not a rung on the same ramp.
enum BrandPalette {
    static let accent = Color.accentColor
    /// Accent's hue, so tone(_:of:) stays visually tied to AccentColor even
    /// if the asset's exact RGB ever changes.
    private static let accentHue = 0.40

    static func tone(_ level: Int, of total: Int) -> Color {
        let t = total > 1 ? Double(max(0, min(level, total - 1))) / Double(total - 1) : 1
        return Color(hue: accentHue, saturation: 0.4 + 0.4 * t, brightness: 0.5 + 0.35 * t)
    }

    static let elite = Color(red: 0.93, green: 0.73, blue: 0.24)

    /// Subtle diagonal brand gradient for the one or two surfaces per screen
    /// that should visually lead, not applied to ordinary cards, which
    /// would flatten the effect back into "everything looks the same".
    static var heroGradient: LinearGradient {
        LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - CardEntrance

/// A brief, index-staggered rise-and-fade the first time a card appears, so
/// a screen full of stacked cards feels composed rather than dropped in all
/// at once as a single static layout. Purely a one-shot `onAppear` animation
/// on local `@State`: no ongoing cost once settled, no effect on layout or
/// hit-testing before/after.
struct CardEntrance: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(Double(index) * 0.04)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func cardEntrance(_ index: Int) -> some View { modifier(CardEntrance(index: index)) }
}

// MARK: - RollingNumberText

/// A number that interpolates through intermediate values instead of
/// snapping: SwiftUI animates `animatableData`, re-rendering the text at
/// each intermediate value, so wrapping a change in an animation (or
/// attaching `.animation(_:value:)` above this view) makes the number
/// visibly count up/down. Inherits font/color from the environment like
/// any Text. This is the telemetry-dial feel: a metric that *arrives* at
/// its value rather than teleporting to it.
struct RollingNumberText: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))")
    }
}

// MARK: - BrandScreenBackground

/// The shared screen backdrop: base grouped background with a faint brand
/// glow bleeding down from the top, so every hub screen sits under the
/// same ambient light source instead of each being its own flat gray
/// void. One modifier everywhere is also what makes the screens read as
/// one product: see the design rule that every screen should feel
/// related to every other screen.
struct BrandScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Color(.systemGroupedBackground)
                    LinearGradient(colors: [BrandPalette.accent.opacity(0.10), .clear],
                                   startPoint: .top, endPoint: .center)
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func brandScreenBackground() -> some View { modifier(BrandScreenBackground()) }
}

/// Consistent card chrome used across every card in the app. Built for the
/// app's committed dark look (see INFOPLIST_KEY_UIUserInterfaceStyle): a
/// soft fill with a faint top-edge "sheen" gradient so each card reads as a
/// lit surface with depth rather than a flat gray rectangle, the single
/// biggest tell separating premium dark UIs (Whoop, Oura) from default
/// dark-mode grays, plus a hairline border whose top edge is slightly
/// brighter than its sides, mimicking how light actually falls on a raised
/// surface. Still renders sensibly in light mode (the sheen fades to
/// near-invisible) in case the forced style is ever reverted.
struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.07 : 0.25), .clear],
                                   startPoint: .top, endPoint: .center)
                }
                .clipShape(RoundedRectangle(cornerRadius: CardMetrics.cornerRadius, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: CardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                                                Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.04), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}

/// The elevated counterpart to CardBackground: a translucent brand-tinted
/// wash over the same neutral base (not a solid fill: AccentColor is a
/// bright, light green, so a solid fill would fight legibility for
/// .primary/.secondary text that assumes a neutral background), plus a
/// colored border and glow shadow instead of the barely-visible neutral
/// shadow every ordinary card uses. Reserved for the one hero surface per
/// screen (the Today dashboard's score card); using it more broadly would
/// just flatten the effect back into "everything looks the same", the
/// exact problem it exists to fix.
struct HeroCardBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    LinearGradient(colors: [BrandPalette.accent.opacity(0.18), BrandPalette.accent.opacity(0.03)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .clipShape(RoundedRectangle(cornerRadius: CardMetrics.cornerRadius, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: CardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(BrandPalette.accent.opacity(colorScheme == .dark ? 0.38 : 0.22), lineWidth: 1)
            )
            .shadow(color: BrandPalette.accent.opacity(colorScheme == .dark ? 0.2 : 0.16), radius: 18, x: 0, y: 8)
    }
}

extension View {
    func heroCardBackground() -> some View { modifier(HeroCardBackground()) }
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
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
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
    @State private var appeared = false

    private var progress: Double { target > 0 ? min(1.2, current / target) : 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.16), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: appeared ? min(1, progress) : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    RollingNumberText(value: appeared ? current : 0)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }
            .frame(width: 60, height: 60)
            // Ring sweeps and number counts up together on first appear;
            // later data edits animate through the same channel because
            // `progress`/`current` changes are also value-triggered here.
            .animation(.easeOut(duration: 0.9), value: appeared)
            .animation(.snappy(duration: 0.45), value: progress)
            .onAppear { appeared = true }
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
    @State private var appeared = false

    private var progress: Double { maxScore > 0 ? max(0, min(1, score / maxScore)) : 0 }
    private var isFull: Bool { maxScore > 0 && score >= maxScore }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: appeared ? progress : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // A completed ring earns a glow: the milestone reads in
                    // the lighting, not just the number.
                    .shadow(color: color.opacity(isFull && appeared ? 0.55 : 0), radius: 10)
                VStack(spacing: 0) {
                    RollingNumberText(value: appeared ? score.rounded() : 0)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(color)
                    Text("/\(Int(maxScore))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            .animation(.easeOut(duration: 0.9), value: appeared)
            .animation(.snappy(duration: 0.45), value: progress)
            .onAppear { appeared = true }
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

/// Compact value readout used by interactive trend charts. Keeping the
/// presentation shared means every chart reports selected points with the
/// same date, typography, and exact-value hierarchy.
struct ChartPointCallout: View {
    let date: Date
    let values: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Formatters.mediumDate(date))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Text(item.label)
                    Spacer(minLength: 8)
                    Text(item.value)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minWidth: 104)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

// MARK: - IconBadge

/// A tinted circular badge behind an SF Symbol, used wherever a glyph is the
/// focal point of what it's next to (empty states, hero surfaces) so it
/// reads as a designed element rather than a bare system icon floating on
/// the page background. Not used for the small header icons inside
/// DashboardCard; those are deliberately minimal secondary labels, and a
/// badge there would fight the label instead of supporting it.
struct IconBadge: View {
    let systemImage: String
    var color: Color = BrandPalette.accent
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: Circle())
    }
}

// MARK: - EmptyStateView

/// A quiet, non-demo empty state: a badged glyph, a short title, and one line
/// of guidance. No illustrations, no sample data; just what to do next.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            IconBadge(systemImage: systemImage, color: .secondary, size: 48)
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

    private static let tierThresholds: [Double] = [150, 300, 450, 600, 750, 900]

    private var levelColor: Color {
        let tier = Self.tierThresholds.firstIndex { score.score < $0 } ?? Self.tierThresholds.count
        return tier == Self.tierThresholds.count
            ? BrandPalette.elite
            : BrandPalette.tone(tier, of: Self.tierThresholds.count + 1)
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
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
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
