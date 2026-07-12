import SwiftUI

// MARK: - Formatting helpers

enum MenuFormat {
    static func price(_ amount: Double?, code: String) -> String? {
        guard let amount, amount > 0 else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
        return f.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }

    /// Distance respecting the user's unit system (km vs miles).
    static func distance(_ meters: Double?, imperial: Bool) -> String? {
        guard let meters else { return nil }
        if imperial {
            let miles = meters / 1609.34
            return miles < 0.1 ? "nearby" : String(format: "%.1f mi", miles)
        }
        if meters < 100 { return "nearby" }
        if meters < 1000 { return "\(Int(meters / 10) * 10) m" }
        return String(format: "%.1f km", meters / 1000)
    }
}

// MARK: - Score visual language
// Health and Satiety are deliberately different shapes and colour families so
// they can never be mistaken for one another: Health is a GREEN RING with a
// heart glyph; Satiety is a BLUE FILL BAR with a gauge glyph.

/// The Health score's colour, reusing the food log's shared tiering.
private func healthColor(_ score: Double) -> Color { MealScoreTier(score).color }

/// Satiety uses a distinct blue→indigo scale, never green/red.
private func satietyColor(_ score: Double) -> Color {
    switch score {
    case 75...: return .indigo
    case 55..<75: return .blue
    case 35..<55: return .cyan
    default: return .gray
    }
}

/// Large Health ring — green, heart glyph, "HEALTH".
struct HealthScoreGauge: View {
    let score: Double
    var size: CGFloat = 76

    var body: some View {
        let color = healthColor(score)
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(color.opacity(0.16), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0, min(1, score / 100)))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -1) {
                    Image(systemName: "heart.fill").font(.system(size: size * 0.16)).foregroundStyle(color)
                    Text("\(Int(score.rounded()))")
                        .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                }
            }
            .frame(width: size, height: size)
            Text("HEALTH")
                .font(.system(size: 10, weight: .heavy)).tracking(1)
                .foregroundStyle(color)
        }
        .accessibilityElement()
        .accessibilityLabel("Health score \(Int(score)) out of 100")
    }
}

/// Large Satiety gauge — blue vertical fill bar with a gauge glyph, "SATIETY".
struct SatietyScoreGauge: View {
    let score: Double
    var size: CGFloat = 76

    var body: some View {
        let color = satietyColor(score)
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(color.opacity(0.16), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0, min(1, score / 100)))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -1) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: size * 0.16)).foregroundStyle(color)
                    Text("\(Int(score.rounded()))")
                        .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                }
            }
            .frame(width: size, height: size)
            Text("SATIETY")
                .font(.system(size: 10, weight: .heavy)).tracking(1)
                .foregroundStyle(color)
        }
        .accessibilityElement()
        .accessibilityLabel("Satiety score \(Int(score)) out of 100")
    }
}

/// Compact Health chip (green heart) for cards.
struct HealthChip: View {
    let score: Double
    var body: some View {
        let color = healthColor(score)
        HStack(spacing: 3) {
            Image(systemName: "heart.fill").font(.system(size: 9))
            Text("\(Int(score.rounded()))").font(.system(.subheadline, design: .rounded, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// Compact Satiety chip (blue gauge) for cards.
struct SatietyChip: View {
    let score: Double
    var body: some View {
        let color = satietyColor(score)
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent").font(.system(size: 9))
            Text("\(Int(score.rounded()))").font(.system(.subheadline, design: .rounded, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Source & confidence

/// Honest source label — official vs the various estimate tiers, never blurred.
struct NutritionSourceBadge: View {
    let kind: NutritionSourceKind
    var compact = false

    private var color: Color {
        switch kind {
        case .official: return .green
        case .restaurantProvided: return .teal
        case .estimatedFromIngredients: return .orange
        case .lowConfidenceEstimate: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.systemImage).font(.system(size: 9, weight: .bold))
            Text(compact ? kind.shortLabel : kind.label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// Three dots for high/medium/low confidence.
struct ConfidenceDots: View {
    let confidence: NutritionConfidence
    private var filled: Int {
        switch confidence { case .high: return 3; case .medium: return 2; case .low: return 1 }
    }
    var body: some View {
        HStack(spacing: 3) {
            Text("Confidence").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i < filled ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18))
                        .frame(width: 5, height: 5)
                }
            }
            Text(confidence.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bold macro readout (F1-telemetry style)

/// A tight row of big macro numbers: the calorie hero plus P/C/F/fibre.
struct MacroReadout: View {
    let nutrition: ResolvedNutrition
    var showOil = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(nutrition.calories))")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text("KCAL").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.secondary)
            }
            macro("P", nutrition.protein, .red)
            macro("C", nutrition.carbs, .blue)
            macro("F", nutrition.fat, .yellow)
            macro("Fib", nutrition.fiber, .green)
        }
    }

    private func macro(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Int(value.rounded()))")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(.secondary)
        }
    }
}
