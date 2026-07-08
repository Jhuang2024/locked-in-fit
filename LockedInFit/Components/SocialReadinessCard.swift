import SwiftUI

/// Subtle, dashboard-only surface for imported Social Climber event context.
/// Read-only: LockedInFit never edits Social Climber's events, it only reacts
/// to them with its own self-improvement suggestions (see
/// EventAwareChecklistService, which adds the actual checklist items).
struct SocialReadinessCard: View {
    let readiness: CrossAppIntegrationManager.SocialReadiness

    var body: some View {
        DashboardCard(title: "Social Day", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 4) {
                Text(readiness.summaryText)
                    .font(.subheadline)
                Text("From your Social Climber calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
