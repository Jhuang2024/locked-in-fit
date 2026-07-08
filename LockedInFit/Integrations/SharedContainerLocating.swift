import Foundation

/// Locates the on-disk container the cross-app JSON bridge reads and writes.
/// Abstracted behind a protocol so `SharedContextStore` degrades to a no-op
/// instead of crashing when App Groups aren't provisioned for this build
/// (no signing team configured, or the App Group entitlement not granted).
protocol SharedContainerLocating {
    var containerURL: URL? { get }
}

/// Where the one-per-install App Group lookup currently stands, for the
/// Social Climber settings screen's live status row.
enum AppGroupLookupState: Equatable {
    /// Never attempted on this launch (and not proven fast on a previous
    /// one). The bridge reports unavailable until the Social Climber
    /// settings screen kicks off the first attempt.
    case notStarted
    /// Attempt running on a background queue right now.
    case checking
    /// Resolved: the shared container exists and the bridge is live.
    case available
    /// Resolved: the OS says there is no container for this app group
    /// (entitlement missing/unprovisioned for this build).
    case unavailable
    /// A previous attempt was slow or never finished, so lookups are
    /// suspended for this install until the user taps Check Again.
    case disabled
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

    static var lookupState: AppGroupLookupState { AppGroupContainerCache.shared.state }

    /// First-attempt trigger, called from the Social Climber settings
    /// screen. Launch never starts a FIRST attempt itself; see
    /// `AppGroupContainerCache` for the policy.
    static func beginResolvingContainer() {
        AppGroupContainerCache.shared.beginResolutionIfNeeded()
    }

    /// Clears the slow/never-finished sentinel and tries again. Explicitly
    /// user-initiated (the Check Again button), so a genuinely broken
    /// provisioning setup can never retry itself in a loop.
    static func retryContainerLookup() {
        AppGroupContainerCache.shared.retry()
    }
}

/// Owns the App Group lookup for the process lifetime.
///
/// History, because the policy below only makes sense with it: on one real
/// device this lookup appeared to take 20-30 seconds (the App Group
/// entitlement looked half-provisioned), and for a while it was the prime
/// suspect for an app-wide freeze. The freeze turned out to be an unrelated
/// SwiftUI navigation bug, so the "slow lookup" was inferred, never
/// measured — but the defenses are kept because they cost nothing when the
/// lookup is healthy and cap the damage if it genuinely is slow somewhere:
///
/// 1. The FIRST attempt on an install only ever starts from the Social
///    Climber settings screen — an explicit, user-visible moment — never
///    from launch or any other hot path. Every attempt is timed and logged
///    (appGroup.lookup.finished in Xs), so slowness is now a measured fact
///    rather than a theory.
/// 2. Once an attempt has completed fast, the install is proven healthy
///    and later launches start the lookup immediately, so the bridge works
///    from launch without another Settings visit.
/// 3. If an attempt measures slower than 3s, or never finishes because the
///    app died mid-attempt, lookups are suspended for the install — but
///    recoverable: the Check Again button clears the sentinel and retries.
///    (An earlier version made this permanent, which false-positively
///    locked the feature out when the app was force-quit during freezes it
///    didn't cause.)
private final class AppGroupContainerCache: @unchecked Sendable {
    static let shared = AppGroupContainerCache()

    private static let attemptStartedKey = "LockedInFit.appGroupLookup.started"
    private static let attemptCompletedKey = "LockedInFit.appGroupLookup.completed"
    private static let markedSlowKey = "LockedInFit.appGroupLookup.markedSlow"
    /// Anything slower than this is treated as the broken-provisioning
    /// case. A healthy lookup is milliseconds.
    private static let slowThresholdSeconds = 3.0

    private let lock = NSLock()
    /// nil = not resolved (not attempted, or attempt in flight);
    /// .some(nil) = resolved or suspended, unavailable;
    /// .some(.some(url)) = resolved, available at url.
    private var resolved: URL??
    private var attemptInFlight = false
    private var suspendedBySentinel = false

    private init() {
        let defaults = UserDefaults.standard
        let previousAttemptNeverFinished = defaults.object(forKey: Self.attemptStartedKey) != nil
            && !defaults.bool(forKey: Self.attemptCompletedKey)
        if defaults.bool(forKey: Self.markedSlowKey) || previousAttemptNeverFinished {
            resolved = .some(nil)
            suspendedBySentinel = true
            PerfLog.event("appGroup.lookup.suspended")
            return
        }
        // A previous attempt on this install completed fast, so the lookup
        // is proven safe here: start it right away so the cross-app bridge
        // works from launch without needing a Settings visit first.
        if defaults.bool(forKey: Self.attemptCompletedKey) {
            beginResolutionIfNeeded()
        }
    }

    var containerURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return resolved ?? nil
    }

    var state: AppGroupLookupState {
        lock.lock()
        defer { lock.unlock() }
        if attemptInFlight { return .checking }
        if suspendedBySentinel { return .disabled }
        switch resolved {
        case .some(.some): return .available
        case .some(.none): return .unavailable
        case .none: return .notStarted
        }
    }

    func beginResolutionIfNeeded() {
        lock.lock()
        if resolved != nil || attemptInFlight {
            lock.unlock()
            return
        }
        attemptInFlight = true
        lock.unlock()

        let defaults = UserDefaults.standard
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

    func retry() {
        lock.lock()
        let alreadyAvailable = (resolved ?? nil) != nil
        if attemptInFlight || alreadyAvailable {
            lock.unlock()
            return
        }
        resolved = nil
        suspendedBySentinel = false
        lock.unlock()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.attemptStartedKey)
        defaults.set(false, forKey: Self.attemptCompletedKey)
        defaults.set(false, forKey: Self.markedSlowKey)
        PerfLog.event("appGroup.lookup.retry")
        beginResolutionIfNeeded()
    }
}
