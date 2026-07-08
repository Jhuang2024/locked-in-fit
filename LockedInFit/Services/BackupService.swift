import Foundation
import SwiftData

/// Automatic and manual local backups of LockedInFit's own data, written as
/// the same JSON snapshot `ExportImportService` already builds for manual
/// export, kept in a directory of their own separate from both the live
/// SwiftData store and the App Group container.
///
/// Every backup, automatic or manual, builds and writes on `BackupActor`, a
/// private `@ModelActor` with its own background-safe `ModelContext`.
/// Fetching, encoding, and writing to disk never touch the main actor or
/// `container.mainContext`. Scheduling (debounce + throttle + in-flight
/// guard) lives on `BackupCoordinator`, a plain actor, so the shared
/// scheduling state can't race even though calls come from the main thread
/// (view code) and background tasks concurrently.
///
/// Automatic backups only ever run after an actual data mutation is
/// reported via `scheduleBackupSoon`; nothing here runs on launch, on
/// backgrounding, or as a side effect of routine notification refreshes.
///
/// Important boundary to be honest about: these backups live inside this
/// app's own sandbox, so they protect against in-app mistakes (a bad
/// migration, an accidental reset) but NOT against a genuine app uninstall,
/// which wipes the whole sandbox, backups included. The only thing that
/// survives an uninstall is a file saved outside the app (Settings →
/// Export JSON, shared to Files/iCloud Drive/AirDrop).
enum BackupService {
    static let maxBackupsKept = 10
    /// Automatic backups never run more often than this, no matter how many
    /// changes happen in between. Only the explicit "Backup Now" button
    /// bypasses it.
    static let minimumAutomaticInterval: TimeInterval = 5 * 60
    fileprivate static let lastAutomaticBackupKey = "LockedInFit.lastAutomaticBackupDate"

    struct BackupInfo: Identifiable {
        enum Location {
            /// Application Support/Backups inside this app's sandbox: fast
            /// and private, but dies with the sandbox when a signing change
            /// makes an update replace the app container.
            case local
            /// The shared App Group container, which survives app
            /// updates/reinstalls; see the mirror functions below.
            case sharedContainer
        }

        let url: URL
        let date: Date
        let recordCount: Int
        var location: Location = .local
        var id: URL { url }
    }

    enum RestoreOutcome {
        case restored(count: Int)
        case emptyBackupSkipped
        case failed(Error)
    }

    /// Tiny per-backup record kept in `index.json`, so listing backups never
    /// has to decode a backup's full (potentially large, months-of-history)
    /// snapshot content just to read its date and record count.
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

    // MARK: - Scheduling (debounced, throttled, background-safe)

    /// Call this after an actual data mutation only: adding a meal, editing
    /// a goal, saving a setting, logging a workout/sleep/check-in, an
    /// import. Never call it from launch, backgrounding, or routine refresh
    /// code, none of which are data-mutation events. Fire-and-forget: hops
    /// onto `BackupCoordinator` to debounce and throttle, never blocking the
    /// caller.
    static func scheduleBackupSoon(container: ModelContainer, after seconds: Double = 3) {
        PerfLog.event("backup.scheduled")
        Task { await BackupCoordinator.shared.scheduleSoon(container: container, after: seconds) }
    }

    /// Explicit manual "Backup Now": bypasses the throttle, but still
    /// refuses to overlap an in-flight backup. Fully off the main thread;
    /// callers should show their own progress UI around the await for a
    /// large database.
    @discardableResult
    static func backupNowManually(container: ModelContainer) async -> URL? {
        await BackupCoordinator.shared.backupManually(container: container)
    }

    /// The actual work: fetch, encode, write, rotate. Called only from
    /// `BackupActor`'s isolated context, so it always runs off the main
    /// thread. Not private so `BackupActor` (a separate type) can call it.
    static func performBackup(context: ModelContext) -> URL? {
        guard let snapshot = PerfLog.measure("backup.snapshot", { try? ExportImportService.makeSnapshot(context: context) }) else {
            return nil
        }
        let existingIndex = readIndex()
        if snapshot.totalRecordCount == 0, existingIndex.contains(where: { $0.recordCount > 0 }) {
            return nil
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = PerfLog.measure("backup.encode", { try? encoder.encode(snapshot) }) else { return nil }

        let filename = "backup-\(fileStamp(snapshot.exportedAt)).json"
        let destination = backupsDirectory.appendingPathComponent(filename)
        let temp = backupsDirectory.appendingPathComponent(filename + ".tmp-\(UUID().uuidString)")
        let written = PerfLog.measure("backup.write") { () -> Bool in
            do {
                try data.write(to: temp, options: .atomic)
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
                return true
            } catch {
                try? FileManager.default.removeItem(at: temp)
                return false
            }
        }
        guard written else { return nil }

        var updatedIndex = existingIndex
        updatedIndex.append(IndexEntry(filename: filename, date: snapshot.exportedAt, recordCount: snapshot.totalRecordCount))
        writeIndex(updatedIndex)
        rotate()
        mirrorToAppGroup(data: data, date: snapshot.exportedAt, recordCount: snapshot.totalRecordCount)
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
    /// which would be a confusing no-op rather than a real recovery. Runs on
    /// the caller's context (the main context, in every call site) since
    /// it's a rare, explicit, user-confirmed action whose inserted records
    /// need to show up immediately in the UI.
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

    /// Keeps the newest `maxBackupsKept` backups — but NEVER rotates out the
    /// most complete one. After an accidental wipe (an update replacing the
    /// app container), the app starts taking fresh automatic backups of the
    /// nearly-empty post-wipe state; a plain newest-N policy let those push
    /// the one copy of the real data off the end of the list.
    private static func rotate() {
        let sorted = readIndex().sorted { $0.date > $1.date }
        guard sorted.count > maxBackupsKept else { return }
        let bestFilename = sorted.max(by: { $0.recordCount < $1.recordCount })?.filename
        var kept: [IndexEntry] = []
        for (index, entry) in sorted.enumerated() {
            if index < maxBackupsKept || entry.filename == bestFilename {
                kept.append(entry)
            } else {
                try? FileManager.default.removeItem(at: backupsDirectory.appendingPathComponent(entry.filename))
            }
        }
        writeIndex(kept)
    }

    // MARK: - App Group mirrors (survive app updates/reinstalls)

    /// Local backups die with the sandbox when a signing/identity change
    /// makes an app update replace the container — exactly the event backups
    /// exist for. So every backup is also mirrored into the shared App Group
    /// container (when available), which has its own lifecycle and survives
    /// updates: "latest" always tracks the newest backup, and "best" only
    /// ever advances to a backup with at least as many records, so a
    /// post-wipe rebuild can never overwrite the most complete copy.
    private struct MirrorMeta: Codable {
        var date: Date
        var recordCount: Int
    }

    private static var appGroupBackupsDirectory: URL? {
        guard let container = AppGroupContainerLocator().containerURL else { return nil }
        let dir = container.appendingPathComponent("LockedInFitBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func mirrorToAppGroup(data: Data, date: Date, recordCount: Int) {
        guard let dir = appGroupBackupsDirectory else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let meta = try? encoder.encode(MirrorMeta(date: date, recordCount: recordCount)) else { return }

        writeMirror(named: "backup-latest", data: data, meta: meta, in: dir)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bestCount = (try? Data(contentsOf: dir.appendingPathComponent("backup-best.meta.json")))
            .flatMap { try? decoder.decode(MirrorMeta.self, from: $0) }?
            .recordCount ?? -1
        if recordCount >= bestCount {
            writeMirror(named: "backup-best", data: data, meta: meta, in: dir)
        }
    }

    private static func writeMirror(named name: String, data: Data, meta: Data, in dir: URL) {
        try? data.write(to: dir.appendingPathComponent(name + ".json"), options: .atomic)
        try? meta.write(to: dir.appendingPathComponent(name + ".meta.json"), options: .atomic)
    }

    /// The App Group mirror backups, for the restore pickers. Empty when the
    /// shared container is unavailable or no mirror has been written yet.
    static func appGroupMirrorBackups() -> [BackupInfo] {
        guard let dir = appGroupBackupsDirectory else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var output: [BackupInfo] = []
        for name in ["backup-best", "backup-latest"] {
            let file = dir.appendingPathComponent(name + ".json")
            guard FileManager.default.fileExists(atPath: file.path),
                  let metaData = try? Data(contentsOf: dir.appendingPathComponent(name + ".meta.json")),
                  let meta = try? decoder.decode(MirrorMeta.self, from: metaData) else { continue }
            output.append(BackupInfo(url: file, date: meta.date, recordCount: meta.recordCount,
                                     location: .sharedContainer))
        }
        // best and latest are often the same snapshot; no point listing twice.
        if output.count == 2, output[0].date == output[1].date, output[0].recordCount == output[1].recordCount {
            output.removeLast()
        }
        return output
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

/// Owns the scheduling state (pending debounce task, in-flight flag, reused
/// backup actor) on its own actor, so concurrent calls to
/// `BackupService.scheduleBackupSoon`/`backupNowManually` from the main
/// thread and background tasks can't race on shared mutable state the way
/// plain static vars would.
private actor BackupCoordinator {
    static let shared = BackupCoordinator()

    private var pendingTask: Task<Void, Never>?
    private var backupActor: BackupActor?
    private var isRunning = false

    func scheduleSoon(container: ModelContainer, after seconds: Double) {
        pendingTask?.cancel()
        pendingTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.runAutomaticIfDue(container: container)
        }
    }

    private func runAutomaticIfDue(container: ModelContainer) async {
        guard !isRunning else { return }
        if let last = UserDefaults.standard.object(forKey: BackupService.lastAutomaticBackupKey) as? Date,
           Date().timeIntervalSince(last) < BackupService.minimumAutomaticInterval {
            return
        }
        _ = await runBackup(container: container)
    }

    func backupManually(container: ModelContainer) async -> URL? {
        guard !isRunning else { return nil }
        return await runBackup(container: container)
    }

    @discardableResult
    private func runBackup(container: ModelContainer) async -> URL? {
        isRunning = true
        defer { isRunning = false }
        PerfLog.event("backup.started")
        let actor = backupActor ?? BackupActor(modelContainer: container)
        backupActor = actor
        let url = await actor.backupNow()
        PerfLog.event("backup.finished")
        if url != nil {
            UserDefaults.standard.set(Date(), forKey: BackupService.lastAutomaticBackupKey)
        }
        return url
    }
}

/// Private, background-safe `ModelContext` for building and writing backups
/// entirely off the main actor. `@ModelActor` gives this its own
/// actor-isolated context bound to the same persistent store as the app's
/// main context; nothing here ever touches `container.mainContext`.
@ModelActor
actor BackupActor {
    func backupNow() -> URL? {
        BackupService.performBackup(context: modelContext)
    }
}
