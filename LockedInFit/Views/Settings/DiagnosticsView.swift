import SwiftUI
import SwiftData

#if DEBUG
/// Debug-only diagnostics for the persistence/backup system: never compiled
/// into release builds, and only linked from Settings when DEBUG. Exists so
/// a signing/App Group/persistence problem shows up here first instead of
/// being discovered by a user losing data.
struct DiagnosticsView: View {
    @Environment(\.modelContext) private var context
    @State private var recordCount: Int?
    @State private var latestBackup: BackupService.BackupInfo?
    @State private var backupCount = 0

    private var storeDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private var storeFileNames: [String] {
        guard let storeDirectory,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: storeDirectory.path) else { return [] }
        return contents.filter { $0.hasPrefix("default.store") }.sorted()
    }

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "unknown")
            }
            Section("Persistence") {
                LabeledContent("Store directory", value: storeDirectory?.path ?? "unknown")
                if storeFileNames.isEmpty {
                    Text("No store files found yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(storeFileNames, id: \.self) { name in
                        LabeledContent("File", value: name)
                    }
                }
            }
            Section("App Group") {
                LabeledContent("Identifier", value: AppGroupContainerLocator.appGroupIdentifier)
                LabeledContent("Path", value: AppGroupContainerLocator().containerURL?.path ?? "unavailable")
            }
            Section("Record counts") {
                LabeledContent("Total", value: recordCount.map(String.init) ?? "…")
                Text("Total mirrors what BackupService/DataLossGuard use, across every logged category.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Section("Backups") {
                if let latestBackup {
                    LabeledContent("Latest backup", value: Formatters.mediumDate(latestBackup.date))
                    LabeledContent("Latest backup records", value: "\(latestBackup.recordCount)")
                } else {
                    Text("No backups yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Backups kept", value: "\(backupCount) / \(BackupService.maxBackupsKept)")
                LabeledContent("Backups directory", value: BackupService.backupsDirectory.path)
            }
            Section {
                Button("Refresh") { refresh() }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
    }

    /// Pulled into one explicit action (initial appear, or tapping Refresh)
    /// rather than computed inline in the body: decoding every backup
    /// file's full JSON just to read this screen isn't something that
    /// should happen on every unrelated re-render.
    private func refresh() {
        recordCount = DataLossGuard.currentRecordCount(context: context)
        let backups = BackupService.listBackups()
        latestBackup = backups.first
        backupCount = backups.count
    }
}
#endif
