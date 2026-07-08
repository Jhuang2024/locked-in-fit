import SwiftUI
import SwiftData

/// Opt-in Apple Health sync. Renpho weight/body-fat lands here via Apple Health.
struct HealthKitSyncView: View {
    @Environment(\.modelContext) private var context
    @State private var manager = HealthKitManager.shared
    @State private var syncDays = 60

    var body: some View {
        Form {
            Section {
                if manager.isAvailable {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(manager.autoSyncEnabled ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(manager.autoSyncEnabled ? "Auto-sync is on" : "Auto-sync is off")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if manager.syncing {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Text("Refreshes about once a minute while the app is open, and instantly in the background whenever new Health data arrives.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Full history range", selection: $syncDays) {
                        Text("2 weeks").tag(14)
                        Text("2 months").tag(60)
                        Text("6 months").tag(180)
                        Text("All time").tag(0)
                    }
                    Button {
                        Task { await manager.sync(days: syncDays > 0 ? syncDays : nil, context: context) }
                    } label: {
                        if manager.syncing {
                            HStack { ProgressView(); Text("Syncing…") }
                        } else {
                            Label("Sync Full History Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(manager.syncing)
                    if let lastSync = manager.lastSync {
                        LabeledContent("Last sync", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                    }
                    if !manager.lastSyncSummary.isEmpty {
                        Text(manager.lastSyncSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("HealthKit isn't available on this device.", systemImage: "heart.slash")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Reads steps, body mass, body fat %, and active energy. Renpho scale data syncs through Apple Health. Pair the Renpho app with Health and it flows in here. All-time sync can take longer on the first run.")
            }

            Section {
                LabeledContent("Steps", value: "Read")
                LabeledContent("Body mass", value: "Read + write")
                LabeledContent("Body fat %", value: "Read")
                LabeledContent("Active energy", value: "Read")
            } header: {
                Text("Data Types")
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
    }
}
