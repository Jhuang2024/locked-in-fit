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
    /// counts, using `fetchCount` rather than fetching and DTO-converting
    /// every row. This runs on every launch, so it has to stay cheap
    /// regardless of how much history the user has: building a full
    /// `ExportImportService.makeSnapshot` here (as an earlier version did)
    /// meant fetching and converting every row across every table
    /// synchronously on the main thread before the app could even show its
    /// first screen, which for a real amount of data is exactly the kind of
    /// long main-thread stall that gets an app killed by the launch
    /// watchdog. `fetchCount` never materializes the rows at all.
    static func currentRecordCount(context: ModelContext) -> Int {
        func count<T: PersistentModel>(_ type: T.Type) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
        }
        return count(MealLog.self) + count(FoodPreset.self) + count(BodyWeightEntry.self)
            + count(BodyFatEntry.self) + count(MeasurementEntry.self) + count(StepEntry.self)
            + count(ActiveEnergyEntry.self) + count(Goal.self) + count(Workout.self)
            + count(ProgressPhoto.self) + count(DailyChecklistItem.self) + count(SleepLog.self)
            + count(NapLog.self) + count(StrengthScore.self) + count(AppearanceCheckIn.self)
            + count(AppearanceSuggestion.self) + count(WorkoutSchedule.self) + count(HealthScan.self)
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

    /// Everything above only checks at launch. This checks WHILE the app is
    /// already running (see RootTabView's periodic loop), for reports of
    /// data disappearing mid-session with no relaunch in between. If that's
    /// really happening, this is the only way to catch it in the act: it
    /// logs a loud, timestamped fault the instant a large drop is observed,
    /// with the exact before/after counts, so the next Console log finally
    /// pins down WHEN it happens instead of only being discoverable (as a
    /// fait accompli) the next time the app opens.
    static func watchForMidSessionLoss(context: ModelContext, previousCount: Int) -> Int {
        let current = currentRecordCount(context: context)
        if previousCount > 5, current == 0 {
            PerfLog.fault("MID-SESSION DATA LOSS: \(previousCount) -> 0 records while the app was already running, no relaunch")
        } else if previousCount > 20, current < previousCount / 2 {
            PerfLog.fault("MID-SESSION DATA DROP: \(previousCount) -> \(current) records while the app was already running, no relaunch")
        }
        return current
    }
}
