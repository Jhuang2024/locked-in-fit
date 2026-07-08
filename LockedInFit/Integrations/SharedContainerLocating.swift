import Foundation

/// Locates the on-disk container the cross-app JSON bridge reads and writes.
/// Abstracted behind a protocol so `SharedContextStore` degrades to a no-op
/// instead of crashing when App Groups aren't provisioned for this build
/// (no signing team configured, or the App Group entitlement not granted).
protocol SharedContainerLocating {
    var containerURL: URL? { get }
}

/// Looks up the shared App Group container. Returns nil, and never throws,
/// blocks, or crashes, whenever the entitlement is missing or unprovisioned,
/// which is exactly the "App Groups unavailable" case the integration layer
/// is built to fall back through.
struct AppGroupContainerLocator: SharedContainerLocating {
    /// Shared identifier both LockedInFit and Social Climber register under
    /// their App Group capability.
    static let appGroupIdentifier = "group.com.jerry.personalOS"

    /// Never calls FileManager directly; see `AppGroupContainerCache`.
    var containerURL: URL? { AppGroupContainerCache.shared.containerURL }
}

/// Owns the one App Group lookup for the process lifetime — and refuses to
/// run it at all on an install where it has ever been slow.
///
/// Why this is so defensive: on this app's real device/signing
/// configuration, `containerURL(forSecurityApplicationGroupIdentifier:)`
/// blocks 20-30 seconds inside a containermanager XPC call (the App Group
/// entitlement is in a half-provisioned state). Running that on the main
/// thread froze launch outright. Running it on a background queue (the
/// previous fix) turned out to be just as poisonous in a subtler way: the
/// first use of that API can hold process-wide runtime/loader locks for
/// its whole duration, and the Swift runtime needs those same locks to
/// instantiate generic type metadata — which SwiftUI does in bulk the
/// first time any screen is pushed. Result, confirmed by a debugger pause:
/// the main thread deadlocked inside `_swift_getGenericMetadata` on
/// whatever screen the user opened first while the XPC was pending,
/// surviving every higher-level fix because no app code was on the stack.
///
/// So: the lookup runs at most once per install, timed. If it completes
/// quickly (healthy provisioning), everything works and keeps working. If
/// it's ever slow, or a previous attempt never finished (the app was
/// killed mid-hang), the lookup is permanently disabled for this install
/// and the container reports unavailable — a state every caller already
/// treats as normal. A broken App Group gets an inert integration, not a
/// frozen app.
private final class AppGroupContainerCache: @unchecked Sendable {
    static let shared = AppGroupContainerCache()

    private static let attemptStartedKey = "LockedInFit.appGroupLookup.started"
    private static let attemptCompletedKey = "LockedInFit.appGroupLookup.completed"
    private static let markedSlowKey = "LockedInFit.appGroupLookup.markedSlow"
    /// Anything slower than this is treated as the broken-provisioning
    /// case. A healthy lookup is milliseconds; the broken one is 20-30s.
    private static let slowThresholdSeconds = 3.0

    private let lock = NSLock()
    /// nil = lookup still in flight; .some(nil) = resolved, unavailable;
    /// .some(.some(url)) = resolved, available at url.
    private var resolved: URL??

    private init() {
        let defaults = UserDefaults.standard
        let previousAttemptNeverFinished = defaults.object(forKey: Self.attemptStartedKey) != nil
            && !defaults.bool(forKey: Self.attemptCompletedKey)
        if defaults.bool(forKey: Self.markedSlowKey) || previousAttemptNeverFinished {
            resolved = .some(nil)
            PerfLog.event("appGroup.lookup.disabled")
            return
        }

        defaults.set(Date(), forKey: Self.attemptStartedKey)
        defaults.set(false, forKey: Self.attemptCompletedKey)
        PerfLog.event("appGroup.lookup.started")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let start = DispatchTime.now()
            let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroupContainerLocator.appGroupIdentifier)
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            defaults.set(true, forKey: Self.attemptCompletedKey)
            if seconds > Self.slowThresholdSeconds {
                defaults.set(true, forKey: Self.markedSlowKey)
            }
            PerfLog.event(String(format: "appGroup.lookup.finished in %.2fs", seconds))
            self?.lock.lock()
            self?.resolved = .some(url)
            self?.lock.unlock()
        }
    }

    var containerURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return resolved ?? nil
    }
}
