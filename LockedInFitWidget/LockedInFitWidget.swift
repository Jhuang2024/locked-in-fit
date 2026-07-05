import WidgetKit
import SwiftUI
import UIKit

private extension Color {
    /// Mirrors the app's AccentColor asset (not shared with this target).
    static let lockedIn = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.22, green: 0.87, blue: 0.48, alpha: 1)
            : UIColor(red: 0.15, green: 0.78, blue: 0.40, alpha: 1)
    })
}

struct LockedInEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct LockedInTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockedInEntry {
        LockedInEntry(date: .now, snapshot: WidgetSnapshot(
            score: 72, caloriesRemaining: 640, calorieTarget: 2200,
            steps: 6200, stepTarget: 8000, updatedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (LockedInEntry) -> Void) {
        completion(LockedInEntry(date: .now, snapshot: WidgetSharedData.load() ?? placeholder(in: context).snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockedInEntry>) -> Void) {
        let entry = LockedInEntry(date: .now, snapshot: WidgetSharedData.load())
        // The app pushes fresh data via WidgetCenter.reloadAllTimelines() the
        // moment a synced value changes; this periodic refresh is just a
        // fallback in case the app hasn't run in a while.
        let nextRefresh = Date.now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct LockedInFitWidgetEntryView: View {
    var entry: LockedInEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall:
                    smallView(snapshot)
                default:
                    mediumView(snapshot)
                }
            } else {
                emptyView
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private func smallView(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            scoreRing(snapshot.score, size: 44)
            Spacer(minLength: 4)
            Text("\(max(0, snapshot.caloriesRemaining))")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text("kcal left")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private func mediumView(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 16) {
            scoreRing(snapshot.score, size: 60)
            VStack(alignment: .leading, spacing: 10) {
                stat(label: "Calories left", value: "\(max(0, snapshot.caloriesRemaining))")
                stat(label: "Steps", value: "\(snapshot.steps)/\(snapshot.stepTarget)")
            }
            Spacer()
        }
        .padding()
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func scoreRing(_ score: Int, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.lockedIn.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(1, Double(score) / 100))
                .stroke(Color.lockedIn, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
        }
        .frame(width: size, height: size)
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.heart")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open Locked In Fit")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LockedInFitWidget: Widget {
    let kind: String = "LockedInFitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockedInTimelineProvider()) { entry in
            LockedInFitWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Locked In Score")
        .description("Today's score, calories remaining, and steps.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct LockedInFitWidgetBundle: WidgetBundle {
    var body: some Widget {
        LockedInFitWidget()
    }
}
