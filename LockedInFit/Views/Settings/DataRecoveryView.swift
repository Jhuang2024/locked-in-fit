import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Shown instead of the normal app when `DataLossGuard` detects that records
/// existed on a previous launch but are gone now. Uses the same
/// BackupService/ExportImportService machinery as Settings → Data, just
/// surfaced up front instead of waiting for the user to notice and dig
/// through Settings themselves.
struct DataRecoveryView: View {
    @Environment(\.modelContext) private var context
    var onResolved: () -> Void

    @State private var showImporter = false
    @State private var resultMessage: String?
    @State private var confirmStartFresh = false
    /// Every available backup (the local rotation plus the App Group
    /// mirrors that survive reinstalls), sorted most-complete first, since
    /// after a wipe the newest backup is usually of the post-wipe state.
    @State private var backups: [BackupService.BackupInfo] = []
    @State private var checkingSharedContainer = false
    @State private var hasAutoRestored = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Your data appears to be missing", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("LockedInFit had logged data on a previous launch, but the app now shows none. This usually follows a reinstall triggered by a signing or App Group change, not something inside the app deleting it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

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
                        Text("No backup is available on this device or in the shared container.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(backups) { backup in
                            Button {
                                restore(from: backup)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label("Restore \(backup.recordCount) records", systemImage: "clock.arrow.circlepath")
                                    Text("\(Formatters.mediumDate(backup.date))\(backup.location == .sharedContainer ? " · shared container" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Restore from a backup")
                } footer: {
                    if backups.count > 1 {
                        Text("Sorted most-complete first. Pick the entry with the most records from before the data loss, not necessarily the newest one.")
                    }
                }

                Section("Restore from an exported file") {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import JSON Export", systemImage: "square.and.arrow.down")
                    }
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) { confirmStartFresh = true } label: {
                        Text("This is intentional, start fresh")
                    }
                } footer: {
                    Text("Only choose this if you're certain the data loss wasn't accidental. LockedInFit will stop showing this screen and treat the current empty state as normal.")
                }
            }
            .navigationTitle("Data Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // This screen appears at launch right after a wipe: the
                // exact moment the App Group lookup (kicked off in
                // App.init) may still be in flight, and the shared-container
                // mirrors are usually the only backups that survived. Keep
                // re-loading until the lookup settles.
                AppGroupContainerLocator.beginResolvingContainer()
                loadBackups()
                for _ in 0..<20 {
                    let state = AppGroupContainerLocator.lookupState
                    guard state == .checking || state == .notStarted else { break }
                    checkingSharedContainer = true
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    loadBackups()
                }
                checkingSharedContainer = false
                loadBackups()
                autoRestoreIfPossible()
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let count = try ExportImportService.importJSON(from: url, context: context)
                        resultMessage = "Restored \(count) records."
                        if count > 0 { finish() }
                    } catch {
                        resultMessage = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    resultMessage = "Import failed: \(error.localizedDescription)"
                }
            }
            .confirmationDialog("Start fresh with no data?", isPresented: $confirmStartFresh, titleVisibility: .visible) {
                Button("Start Fresh", role: .destructive) {
                    DataLossGuard.acknowledge(context: context)
                    onResolved()
                }
            }
        }
    }

    private func loadBackups() {
        backups = BackupService.allKnownBackups()
    }

    private func restore(from backup: BackupService.BackupInfo) {
        let outcome = BackupService.restore(from: backup, context: context,
                                            currentRecordCount: DataLossGuard.currentRecordCount(context: context))
        switch outcome {
        case .restored(let count) where count > 0:
            resultMessage = "Restored \(count) records."
            finish()
        case .restored:
            // A "successful" import that added zero records: the backup
            // was itself empty. Leaves the screen up rather than resolving
            // into an app that's still empty, so the user still sees their
            // other options (a different backup, an exported file).
            resultMessage = "That backup was empty; nothing to restore."
        case .emptyBackupSkipped:
            resultMessage = "That backup is empty; nothing to restore."
        case .failed(let error):
            resultMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    /// Restores the most-complete backup the instant one is found, so a
    /// wipe with a good backup available never requires the user to notice
    /// this screen and tap through it themselves; merge-only restore makes
    /// this safe to do without confirmation, and the manual list stays
    /// visible underneath as a fallback for the rare case this doesn't
    /// resolve it (an unexpectedly-empty "best" backup, still awaiting a
    /// slow App Group lookup, or truly nothing available yet).
    private func autoRestoreIfPossible() {
        guard !hasAutoRestored, let best = backups.first, best.recordCount > 0 else { return }
        hasAutoRestored = true
        restore(from: best)
    }

    private func finish() {
        DataLossGuard.acknowledge(context: context)
        BackupService.scheduleBackupSoon(container: context.container)
        onResolved()
    }
}
