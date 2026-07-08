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

    /// The one and only trigger for actually resolving the container.
    /// Called from the Social Climber settings screen, never from launch
    /// or any hot path; see `AppGroupContainerCache` for why.
    static func beginResolvingContainer() {
        AppGroupContainerCache.shared.beginResolutionIfNeeded()
    }
}

/// Owns the one App Group lookup for the process lifetime — lazily, opt-in,
/// and never on an install where it has ever been slow.
///
/// Why this is so defensive: on this app's real device/signing
/// configuration, `containerURL(forSecurityApplicationGroupIdentifier:)`
/// blocks 20-30 seconds inside a containermanager XPC call (the App Group
/// entitlement is in a half-provisioned state). Running that on the main
/// thread froze launch outright. Running it on a background queue turned
/// out to be just as poisonous in a subtler way: while that XPC is
/// pending, process-wide runtime/loader locks can be held, and both the
/// Swift runtime (generic metadata instantiation) and SwiftUI's attribute
/// graph need those lock chains — so the main thread deadlocked inside
/// `_swift_getGenericMetadata` / `AG::Graph::propagate_dirty` on whatever
/// screen was first pushed during the window, confirmed by debugger
/// pauses, with no app code on the stack.
///
/// Defense in depth, all of which must pass before FileManager is called:
/// 1. Nothing resolves at launch. The lookup only ever starts when the
///    user opens the Social Climber settings screen
///    (`beginResolutionIfNeeded`). Until then every caller sees
///    "unavailable", a state the whole integration already treats as
///    normal.
/// 2. The attempt is timed. If it ever measures slower than 3 seconds,
///    the install is marked and no future launch ever tries again.
/// 3. If a previous attempt never finished (the app was killed while it
///    hung), the mark is implied and the lookup is likewise permanently
///    disabled.
/// A broken App Group costs an inert cross-app integration, never a
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
    /// nil = not resolved (not attempted, or attempt in flight);
    /// .some(nil) = resolved/disabled, unavailable;
    /// .some(.some(url)) = resolved, available at url.
    private var resolved: URL??
    private var attemptInFlight = false

    var containerURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return resolved ?? nil
    }

    func beginResolutionIfNeeded() {
        lock.lock()
        if resolved != nil || attemptInFlight {
            lock.unlock()
            return
        }

        let defaults = UserDefaults.standard
        let previousAttemptNeverFinished = defaults.object(forKey: Self.attemptStartedKey) != nil
            && !defaults.bool(forKey: Self.attemptCompletedKey)
        if defaults.bool(forKey: Self.markedSlowKey) || previousAttemptNeverFinished {
            resolved = .some(nil)
            lock.unlock()
            PerfLog.event("appGroup.lookup.disabled")
            return
        }

        attemptInFlight = true
        lock.unlock()

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
            guard let self else { return }
            self.lock.lock()
            self.resolved = .some(url)
            self.attemptInFlight = false
            self.lock.unlock()
        }
    }
}
