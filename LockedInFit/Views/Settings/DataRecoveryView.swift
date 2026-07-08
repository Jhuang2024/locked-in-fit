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
    @State private var latestBackup: BackupService.BackupInfo?

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

                Section("Restore from local backup") {
                    if let latestBackup {
                        Text("Backup from \(Formatters.mediumDate(latestBackup.date)), \(latestBackup.recordCount) records.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            restore(from: latestBackup)
                        } label: {
                            Label("Restore This Backup", systemImage: "clock.arrow.circlepath")
                        }
                    } else {
                        Text("No local backup is available on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .onAppear { latestBackup = BackupService.latestBackup() }
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

    private func restore(from backup: BackupService.BackupInfo) {
        let outcome = BackupService.restore(from: backup, context: context,
                                            currentRecordCount: DataLossGuard.currentRecordCount(context: context))
        switch outcome {
        case .restored(let count):
            resultMessage = "Restored \(count) records."
            finish()
        case .emptyBackupSkipped:
            resultMessage = "That backup is empty; nothing to restore."
        case .failed(let error):
            resultMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func finish() {
        DataLossGuard.acknowledge(context: context)
        BackupService.scheduleBackupSoon(container: context.container)
        onResolved()
    }
}
