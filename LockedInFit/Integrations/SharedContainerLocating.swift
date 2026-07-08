import Foundation

/// Locates the on-disk container the cross-app JSON bridge reads and writes.
/// Abstracted behind a protocol so `SharedContextStore` degrades to a no-op
/// instead of crashing when App Groups aren't provisioned for this build
/// (no signing team configured, or the App Group entitlement not granted).
protocol SharedContainerLocating {
    var containerURL: URL? { get }
}

/// Where the App Group lookup currently stands, for the Social Climber
/// settings screen and the restore pickers.
enum AppGroupLookupState: Equatable {
    case notStarted
    /// Attempt running on a background queue right now.
    case checking
    /// Resolved: the shared container exists.
    case available
    /// Resolved: the OS says there is no container for this app group
    /// (entitlement missing/unprovisioned for this build).
    case unavailable
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

    static func beginResolvingContainer() {
        AppGroupContainerCache.shared.beginResolutionIfNeeded()
    }

    /// Re-runs a lookup that resolved unavailable (the Check Again button).
    static func retryContainerLookup() {
        AppGroupContainerCache.shared.retry()
    }
}

/// Owns the App Group lookup for the process lifetime: one timed attempt on
/// a background utility queue, kicked off at LAUNCH, with every caller
/// reading the cached answer without ever blocking.
///
/// Resolving at launch is load-bearing for data safety, which is why this
/// is no longer lazy or sentinel-suppressed. Backups are mirrored into the
/// shared container precisely because the app's sandbox (and everything in
/// it, backups included) gets replaced when a signing change makes an
/// update reinstall the container — and any "only resolve after the user
/// visits a settings screen" gate stored in UserDefaults gets wiped right
/// along with it. A previous design did exactly that, so after every wipe
/// the mirrors silently stopped being written AND the restore pickers
/// couldn't see the mirrors that did exist. (That lazy design was armor
/// against a launch-freeze theory that was later disproven — the freeze
/// was an unrelated SwiftUI navigation-loop bug. The lookup itself runs on
/// a background queue, blocks nothing, and its duration is logged:
/// appGroup.lookup.finished in Xs.)
private final class AppGroupContainerCache: @unchecked Sendable {
    static let shared = AppGroupContainerCache()

    private let lock = NSLock()
    /// nil = not resolved (not attempted, or attempt in flight);
    /// .some(nil) = resolved, unavailable;
    /// .some(.some(url)) = resolved, available at url.
    private var resolved: URL??
    private var attemptInFlight = false

    var containerURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return resolved ?? nil
    }

    var state: AppGroupLookupState {
        lock.lock()
        defer { lock.unlock() }
        if attemptInFlight { return .checking }
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

        PerfLog.event("appGroup.lookup.started")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let start = DispatchTime.now()
            let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroupContainerLocator.appGroupIdentifier)
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
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
        lock.unlock()
        PerfLog.event("appGroup.lookup.retry")
        beginResolutionIfNeeded()
    }
}
