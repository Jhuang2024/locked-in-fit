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

    /// Tiny per-backup record kept in `index.json`, so listing backups never
    /// has to decode a backup's full (potentially large, months-of-history)
    /// snapshot content just to read its date and record count. Decoding
    /// full snapshot content on every list call was expensive enough to
    /// stall the main thread, especially for backups made back when there
    /// was more data logged than there is now.
    private struct IndexEntry: Codable {
        var filename: String
        var date: Date
        var recordCount: Int
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

    private static var indexURL: URL { backupsDirectory.appendingPathComponent("index.json") }

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
        let existingIndex = readIndex()
        if snapshot.totalRecordCount == 0, existingIndex.contains(where: { $0.recordCount > 0 }) {
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

        var updatedIndex = existingIndex
        updatedIndex.append(IndexEntry(filename: filename, date: snapshot.exportedAt, recordCount: snapshot.totalRecordCount))
        writeIndex(updatedIndex)
        rotate()
        return destination
    }

    /// All local backups, newest first. Reads the small index file rather
    /// than decoding every backup's full content; falls back to a one-time
    /// full decode only if the index is missing (e.g. backups made before
    /// this index existed), then persists an index so that only happens once.
    static func listBackups() -> [BackupInfo] {
        let indexed = readIndex()
        if !indexed.isEmpty {
            return indexed
                .filter { FileManager.default.fileExists(atPath: backupsDirectory.appendingPathComponent($0.filename).path) }
                .map { BackupInfo(url: backupsDirectory.appendingPathComponent($0.filename), date: $0.date, recordCount: $0.recordCount) }
                .sorted { $0.date > $1.date }
        }

        let files = (try? FileManager.default.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: nil)) ?? []
        let decoded = files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }
            .compactMap(decodeInfoFromFullFile)
            .sorted { $0.date > $1.date }
        if !decoded.isEmpty {
            writeIndex(decoded.map { IndexEntry(filename: $0.url.lastPathComponent, date: $0.date, recordCount: $0.recordCount) })
        }
        return decoded
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

    // MARK: - Index helpers

    private static func readIndex() -> [IndexEntry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([IndexEntry].self, from: data)) ?? []
    }

    private static func writeIndex(_ entries: [IndexEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func rotate() {
        let sorted = readIndex().sorted { $0.date > $1.date }
        guard sorted.count > maxBackupsKept else { return }
        for stale in sorted.suffix(from: maxBackupsKept) {
            try? FileManager.default.removeItem(at: backupsDirectory.appendingPathComponent(stale.filename))
        }
        writeIndex(Array(sorted.prefix(maxBackupsKept)))
    }

    /// Only used for the one-time migration of backups that predate the
    /// index file; never called on the normal listing path.
    private static func decodeInfoFromFullFile(_ url: URL) -> BackupInfo? {
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
