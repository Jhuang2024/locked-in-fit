import Foundation
import os

/// Runs before the SwiftData `ModelContainer` is created. Two
/// responsibilities, both read-only with respect to the live store (this
/// never deletes or migrates anything itself):
///
/// 1. If the app's tracked schema version has changed since the last
///    launch, copy whatever raw store files already exist into the backups
///    directory before SwiftData gets a chance to open (and possibly
///    migrate) them. A byte-for-byte safety net that doesn't depend on the
///    container opening successfully, since it runs first.
/// 2. Log whenever the store's on-disk directory or the App Group container
///    path changes between launches, so a future signing/provisioning
///    change like the one that prompted this feature leaves a trail instead
///    of silently swapping containers.
///
/// Bump `currentSchemaVersion` by hand whenever a `@Model` type gains or
/// loses a persisted property, or the container's type list in
/// `LockedInFitApp` changes, so a real migration always gets a
/// pre-migration snapshot. See the additive-only migration policy documented
/// next to `ModelContainer(for:)` in LockedInFitApp.
enum PersistenceGuard {
    static let currentSchemaVersion = 4 // v4: FoodItem.order added

    private static let logger = Logger(subsystem: "com.jerryhuang.LockedInFit", category: "PersistenceGuard")
    private static let lastSeenSchemaVersionKey = "LockedInFit.lastSeenSchemaVersion"
    private static let lastSeenStorePathKey = "LockedInFit.lastSeenStorePath"
    private static let lastSeenAppGroupPathKey = "LockedInFit.lastSeenAppGroupPath"

    /// Call once, synchronously, before `ModelContainer(for:)` is constructed.
    static func runPreLaunchChecks() {
        backupStoreFilesIfSchemaChanged()
        logPathChangesIfAny()
    }

    /// Best-effort: SwiftData's default (no explicit `ModelConfiguration`)
    /// store is named "default.store" (plus -wal/-shm) directly under
    /// Application Support. If a future SwiftData version changes that
    /// convention, this simply finds nothing to copy and no-ops rather than
    /// failing, since it's a safety net on top of the real backups, not the
    /// only one.
    private static func backupStoreFilesIfSchemaChanged() {
        let defaults = UserDefaults.standard
        let lastSeen = defaults.integer(forKey: lastSeenSchemaVersionKey)
        defer { defaults.set(currentSchemaVersion, forKey: lastSeenSchemaVersionKey) }
        guard lastSeen != currentSchemaVersion else { return }

        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let contents = try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) else {
            return
        }
        let storeFiles = contents.filter { $0.lastPathComponent.hasPrefix("default.store") }
        guard !storeFiles.isEmpty else { return }

        let stamp = BackupService.fileStamp(.now)
        let destination = BackupService.backupsDirectory
            .appendingPathComponent("pre-migration-v\(lastSeen)-to-v\(currentSchemaVersion)-\(stamp)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)) != nil else { return }
        for file in storeFiles {
            _ = try? FileManager.default.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
        }
        logger.notice("Schema version changed (\(lastSeen) -> \(currentSchemaVersion)); copied \(storeFiles.count) store file(s) to \(destination.path, privacy: .public)")
    }

    /// Bytes across every `default.store*` file (the main SQLite file plus
    /// its -wal/-shm journals) currently on disk. Diagnostic, not
    /// protective: this is what tells apart two very differently-caused
    /// versions of "the app shows 0 records" —
    /// - file still large (hundreds of KB+) but SwiftData reports 0 rows:
    ///   SwiftData failed to open/recognize the existing store and silently
    ///   substituted an empty one, the data is still sitting right there on
    ///   disk;
    /// - file is tiny (a few KB, an empty store's baseline size): the store
    ///   itself was genuinely replaced/reset, not a SwiftData read failure.
    /// Logged at every launch and attached to a DataLossGuard incident when
    /// one is detected, so a future occurrence carries the evidence needed
    /// to tell these apart instead of remaining a total mystery.
    static func storeFileSizeBytes() -> Int64 {
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: supportDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return contents
            .filter { $0.lastPathComponent.hasPrefix("default.store") }
            .reduce(Int64(0)) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return total + Int64(size)
            }
    }

    private static func logPathChangesIfAny() {
        let defaults = UserDefaults.standard
        let storePath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? "unknown"
        let groupPath = AppGroupContainerLocator().containerURL?.path ?? "unavailable"

        if defaults.string(forKey: lastSeenStorePathKey) != storePath {
            logger.notice("Persistence store directory is now \(storePath, privacy: .public)")
            defaults.set(storePath, forKey: lastSeenStorePathKey)
        }
        if defaults.string(forKey: lastSeenAppGroupPathKey) != groupPath {
            logger.notice("App Group container path is now \(groupPath, privacy: .public)")
            defaults.set(groupPath, forKey: lastSeenAppGroupPathKey)
        }
    }

    /// Read-only listing of what's actually sitting in the shared App Group
    /// container right now, logged at every launch (not gated to a path
    /// change, unlike the two checks above — this is specifically to catch
    /// a sibling app writing something unexpected there). Exists because of
    /// a report that opening Social Climber while LockedInFit is closed
    /// appears to wipe LockedInFit's data: LockedInFit's own live SwiftData
    /// store is not placed in this shared container by any code in this
    /// app (only the backup mirror and the small cross-app JSON bridge
    /// files are), so this can't explain that report on its own, but if a
    /// sibling app is doing something unexpected to the SHARED container
    /// (touching more than its own namespaced files, or something at the
    /// container root), this log is what would show it.
    static func logAppGroupContentsIfAvailable() {
        guard let container = AppGroupContainerLocator().containerURL else { return }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: container.path)) ?? []
        logger.notice("App Group container contents: \(entries.joined(separator: ", "), privacy: .public)")
    }
}
