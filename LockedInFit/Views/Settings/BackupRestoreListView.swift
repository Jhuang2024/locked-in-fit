import SwiftUI
import SwiftData

/// Picker over every available backup — the local rotation plus the App
/// Group mirrors that survive reinstalls — instead of blindly restoring the
/// newest. This distinction is the whole point: after an update wipes the
/// app container, the NEWEST backup is usually a backup of the post-wipe,
/// nearly-empty state (the app resumed auto-backing-up immediately), while
/// the one the user actually wants is the most COMPLETE one. So that's the
/// sort order, and the badge.
struct BackupRestoreListView: View {
    @Environment(\.modelContext) private var context

    @State private var backups: [BackupService.BackupInfo] = []
    @State private var pendingRestore: BackupService.BackupInfo?
    @State private var result: String?
    @State private var checkingSharedContainer = false

    var body: some View {
        Form {
            Section {
                if checkingSharedContainer {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking the shared container for backups…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if backups.isEmpty && !checkingSharedContainer {
                    Text("No backups found on this device or in the shared container yet. Backups are taken automatically as you use the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(backups) { backup in
                    Button {
                        pendingRestore = backup
                    } label: {
                        row(backup)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Choose a backup")
            } footer: {
                Text("Sorted most-complete first. Restoring merges the backup's records into what's on the device now; nothing is deleted. If an app update wiped your data, pick the entry with the most records — not necessarily the newest one.")
            }

            if let result {
                Section {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Restore From Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // The shared-container mirrors are the backups most likely to
            // matter (they survive the wipes), so make sure the container
            // is resolved — and keep re-loading while the background
            // lookup runs — before concluding "no backups".
            AppGroupContainerLocator.beginResolvingContainer()
            load()
            for _ in 0..<20 {
                let state = AppGroupContainerLocator.lookupState
                guard state == .checking || state == .notStarted else { break }
                checkingSharedContainer = true
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                load()
            }
            checkingSharedContainer = false
            load()
        }
        .confirmationDialog("Restore this backup?",
                            isPresented: Binding(get: { pendingRestore != nil },
                                                 set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingRestore) { backup in
            Button("Restore \(backup.recordCount) records") { restore(backup) }
        }
    }

    private func load() {
        backups = (BackupService.listBackups() + BackupService.appGroupMirrorBackups())
            .sorted {
                if $0.recordCount != $1.recordCount { return $0.recordCount > $1.recordCount }
                return $0.date > $1.date
            }
    }

    private func row(_ backup: BackupService.BackupInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Formatters.mediumDate(backup.date))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if backup.recordCount == backups.first?.recordCount {
                    Text("Most complete")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            Text("\(backup.recordCount) records\(backup.location == .sharedContainer ? " · shared container (survives reinstall)" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func restore(_ backup: BackupService.BackupInfo) {
        let currentCount = DataLossGuard.currentRecordCount(context: context)
        switch BackupService.restore(from: backup, context: context, currentRecordCount: currentCount) {
        case .restored(let count):
            result = "Restored \(count) records from the \(Formatters.mediumDate(backup.date)) backup."
            DataLossGuard.acknowledge(context: context)
            BackupService.scheduleBackupSoon(container: context.container)
        case .emptyBackupSkipped:
            result = "That backup is empty; nothing to restore."
        case .failed(let error):
            result = "Restore failed: \(error.localizedDescription)"
        }
    }
}
