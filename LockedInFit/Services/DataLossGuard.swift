import Foundation
import SwiftData

/// Detects the specific failure mode that prompted this whole safety net:
/// the app launching to find zero records where there were previously many.
/// A sudden drop to zero almost always means something happened outside
/// LockedInFit's own logic (a reinstall, a bad migration), not that the user
/// genuinely deleted everything by hand in one sitting, so it's surfaced as
/// a recovery screen instead of silently continuing into an empty app.
enum DataLossGuard {
    private static let lastKnownRecordCountKey = "LockedInFit.lastKnownRecordCount"

    /// Total records across the same categories `Snapshot.totalRecordCount`
    /// counts, so this and the backup "is this empty" check always agree.
    static func currentRecordCount(context: ModelContext) -> Int {
        (try? ExportImportService.makeSnapshot(context: context))?.totalRecordCount ?? 0
    }

    /// Compares today's count against the last-known count. Only updates the
    /// stored baseline when nothing looks wrong, so a detected loss keeps
    /// being flagged on every launch until it's actually resolved (restored,
    /// imported, or explicitly acknowledged), not just once.
    static func checkForSuddenDataLoss(context: ModelContext) -> Bool {
        let defaults = UserDefaults.standard
        let previous = defaults.integer(forKey: lastKnownRecordCountKey)
        let current = currentRecordCount(context: context)
        let lostEverything = previous > 0 && current == 0
        if !lostEverything {
            defaults.set(current, forKey: lastKnownRecordCountKey)
        }
        return lostEverything
    }

    /// Call after the user has handled a detected loss (restored from a
    /// backup, imported a file, or explicitly confirmed starting fresh), so
    /// the same state isn't flagged again on the next launch.
    static func acknowledge(context: ModelContext) {
        UserDefaults.standard.set(currentRecordCount(context: context), forKey: lastKnownRecordCountKey)
    }
}
