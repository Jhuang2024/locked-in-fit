import Foundation
import SwiftData

/// Automatic and manual local backups of LockedInFit's own data, written as
/// the same JSON snapshot `ExportImportService` already builds for manual
/// export, kept in a directory of their own separate from both the live
/// SwiftData store and the App Group container.
///
/// Important boundary to be honest about: these backups live inside this
/// app's own sandbox, so they protect against in-app mistakes (a bad
/// migration, an accidental reset) but NOT against a genuine app uninstall,
/// which wipes the whole sandbox, backups included. The only thing that
/// survives an uninstall is a file saved outside the app (Settings →
/// Export JSON, shared to Files/iCloud Drive/AirDrop).
enum BackupService {
    static let maxBackupsKept = 5

    struct BackupInfo: Identifiable {
        let url: URL
        let date: Date
        let recordCount: Int
        var id: URL { url }
    }

    enum RestoreOutcome {
        case restored(count: Int)
        case emptyBackupSkipped
        case failed(Error)
    }

    /// Application Support/Backups. Distinct from the live store's directory
    /// (Application Support root) and from the App Group container.
    static var backupsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var pendingBackup: DispatchWorkItem?

    /// Coalesces rapid, repeated changes (typing in a field, logging several
    /// sets back to back) into a single backup once things go quiet, instead
    /// of rebuilding and re-encoding a full snapshot on every keystroke.
    /// Call this from anywhere the user just changed something; the actual
    /// work only runs once, `after` seconds since the *last* call.
    static func scheduleBackupSoon(context: ModelContext, after seconds: Double = 2.5) {
        pendingBackup?.cancel()
        let work = DispatchWorkItem { backupNow(context: context) }
        pendingBackup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Builds a fresh snapshot and writes it as a new timestamped backup.
    /// Refuses to write an empty snapshot when a non-empty backup already
    /// exists, so a transient empty read never buries good history (req: never
    /// let an empty state crowd out real data). Rotates old backups afterward.
    @discardableResult
    static func backupNow(context: ModelContext) -> URL? {
        guard let snapshot = try? ExportImportService.makeSnapshot(context: context) else { return nil }
        let existing = listBackups()
        if snapshot.totalRecordCount == 0, existing.contains(where: { $0.recordCount > 0 }) {
            return nil
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return nil }

        let filename = "backup-\(fileStamp(snapshot.exportedAt)).json"
        let destination = backupsDirectory.appendingPathComponent(filename)
        let temp = backupsDirectory.appendingPathComponent(filename + ".tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return nil
        }
        rotate()
        return destination
    }

    /// All local backups, newest first.
    static func listBackups() -> [BackupInfo] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap(decodeInfo)
            .sorted { $0.date > $1.date }
    }

    static func latestBackup() -> BackupInfo? { listBackups().first }

    /// Restores a backup into `context`. Import is always additive (never
    /// deletes existing rows), so the only real guard needed is refusing to
    /// "restore" an empty backup onto a database that already has data,
    /// which would be a confusing no-op rather than a real recovery.
    static func restore(from backup: BackupInfo, context: ModelContext, currentRecordCount: Int) -> RestoreOutcome {
        guard backup.recordCount > 0 || currentRecordCount == 0 else { return .emptyBackupSkipped }
        do {
            let count = try ExportImportService.importJSON(from: backup.url, context: context)
            return .restored(count: count)
        } catch {
            return .failed(error)
        }
    }

    // MARK: - Helpers

    private static func rotate() {
        let files = listBackups()
        guard files.count > maxBackupsKept else { return }
        for stale in files.dropFirst(maxBackupsKept) {
            try? FileManager.default.removeItem(at: stale.url)
        }
    }

    private static func decodeInfo(at url: URL) -> BackupInfo? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(ExportImportService.Snapshot.self, from: data) else { return nil }
        return BackupInfo(url: url, date: snapshot.exportedAt, recordCount: snapshot.totalRecordCount)
    }

    /// Shared with PersistenceGuard's pre-migration backup folder naming, so
    /// there's one timestamp format across every kind of backup this app makes.
    static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
