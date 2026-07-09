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
    private static let incidentLogKey = "LockedInFit.dataLossIncidents"
    private static let maxIncidentsKept = 10

    /// A detected loss event, persisted (not just logged) so it's visible
    /// from inside the app itself — Settings → Data Safety — rather than
    /// only discoverable via Xcode's console at the exact moment it
    /// happens. That distinction matters a lot for a report of data
    /// disappearing hours into ordinary use with no Mac anywhere nearby.
    struct Incident: Codable, Identifiable {
        var id = UUID()
        var date: Date
        /// "launch" (checkForSuddenDataLoss, next app open) or
        /// "mid-session" (watchForMidSessionLoss, no relaunch involved).
        var kind: String
        var previousCount: Int
        var currentCount: Int
        /// PersistenceGuard.storeFileSizeBytes() at the moment this was
        /// detected. The decisive clue for a future occurrence: still large
        /// despite 0 reported records means SwiftData failed to open an
        /// intact store; near-empty means the store itself was actually
        /// replaced. Optional (decodeIfPresent) so it stays compatible with
        /// any incident already persisted before this field existed.
        var storeFileSizeBytes: Int64?
    }

    /// Newest first, for display.
    static func recentIncidents() -> [Incident] {
        guard let data = UserDefaults.standard.data(forKey: incidentLogKey) else { return [] }
        return ((try? JSONDecoder().decode([Incident].self, from: data)) ?? []).sorted { $0.date > $1.date }
    }

    private static func recordIncident(kind: String, previous: Int, current: Int) {
        var incidents = recentIncidents()
        let incident = Incident(date: .now, kind: kind, previousCount: previous, currentCount: current,
                                storeFileSizeBytes: PersistenceGuard.storeFileSizeBytes())
        incidents.insert(incident, at: 0)
        incidents = Array(incidents.prefix(maxIncidentsKept))
        guard let data = try? JSONEncoder().encode(incidents) else { return }
        UserDefaults.standard.set(data, forKey: incidentLogKey)
    }

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

    /// First pass of the launch check: compares today's count against the
    /// last-known count, but does NOT record an incident or update the
    /// baseline on a possible loss — the caller must confirm this a beat
    /// later with `confirmSuddenLoss` before treating it as real. A single,
    /// immediate read right at launch can catch the store mid-open, the
    /// same false-positive risk Social Climber's bridge fixed on its side;
    /// this mirrors that fix so a transient zero here never trips the
    /// disruptive recovery screen on its own.
    static func checkForPossibleSuddenLoss(context: ModelContext) -> Int? {
        let defaults = UserDefaults.standard
        let previous = defaults.integer(forKey: lastKnownRecordCountKey)
        let current = currentRecordCount(context: context)
        guard previous > 0, current == 0 else {
            defaults.set(current, forKey: lastKnownRecordCountKey)
            return nil
        }
        return previous
    }

    /// Second pass, called ~750ms after `checkForPossibleSuddenLoss`
    /// returned a non-nil `previous`, with a freshly-read count. Only
    /// records the incident (and keeps flagging it on every launch until
    /// actually resolved) once the zero reading is confirmed to still be
    /// zero; any other reading is treated as the transient blip it was and
    /// becomes the new baseline instead.
    static func confirmSuddenLoss(previous: Int, confirmedCurrent: Int) -> Bool {
        guard confirmedCurrent == 0 else {
            UserDefaults.standard.set(confirmedCurrent, forKey: lastKnownRecordCountKey)
            return false
        }
        recordIncident(kind: "launch", previous: previous, current: confirmedCurrent)
        return true
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
            recordIncident(kind: "mid-session", previous: previousCount, current: current)
        } else if previousCount > 20, current < previousCount / 2 {
            PerfLog.fault("MID-SESSION DATA DROP: \(previousCount) -> \(current) records while the app was already running, no relaunch")
            recordIncident(kind: "mid-session", previous: previousCount, current: current)
        }
        return current
    }
}
