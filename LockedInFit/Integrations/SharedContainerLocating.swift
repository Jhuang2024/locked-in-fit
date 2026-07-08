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

    /// Never calls FileManager directly: on at least one real device/signing
    /// configuration, `containerURL(forSecurityApplicationGroupIdentifier:)`
    /// took 20-30 seconds to resolve (this app's App Group entitlement has
    /// been in an ambiguous, half-provisioned state the whole time), and a
    /// plain cached `static let` still blocks whichever thread happens to
    /// touch it first, which from SwiftUI view code is the main thread,
    /// hard-freezing the entire app for the whole 20-30 seconds. See
    /// `AppGroupContainerCache` below, which runs the lookup on a background
    /// queue and is never waited on synchronously.
    var containerURL: URL? { AppGroupContainerCache.shared.containerURL }
}

/// Owns the one App Group lookup for the process lifetime, off the main
/// thread. Every caller reads `containerURL` immediately: it returns nil
/// (indistinguishable from "unavailable", which the whole integration layer
/// already treats as a normal, fail-safe state) until the background lookup
/// finishes, however long that takes. Nothing ever blocks waiting for it.
private final class AppGroupContainerCache: @unchecked Sendable {
    static let shared = AppGroupContainerCache()

    private let lock = NSLock()
    /// nil = lookup still in flight; .some(nil) = resolved, unavailable;
    /// .some(.some(url)) = resolved, available at url.
    private var resolved: URL??

    private init() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroupContainerLocator.appGroupIdentifier)
            self?.lock.lock()
            self?.resolved = url
            self?.lock.unlock()
        }
    }

    var containerURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return resolved ?? nil
    }
}
