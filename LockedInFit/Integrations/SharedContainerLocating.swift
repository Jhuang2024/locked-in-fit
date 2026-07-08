import Foundation

/// Locates the on-disk container the cross-app JSON bridge reads and writes.
/// Abstracted behind a protocol so `SharedContextStore` degrades to a no-op
/// instead of crashing when App Groups aren't provisioned for this build
/// (no signing team configured, or the App Group entitlement not granted).
protocol SharedContainerLocating {
    var containerURL: URL? { get }
}

/// Looks up the shared App Group container. Returns nil, and never throws or
/// crashes, whenever the entitlement is missing or unprovisioned, which is
/// exactly the "App Groups unavailable" case the integration layer is built
/// to fall back through.
struct AppGroupContainerLocator: SharedContainerLocating {
    /// Shared identifier both LockedInFit and Social Climber register under
    /// their App Group capability.
    static let appGroupIdentifier = "group.com.jerry.personalOS"

    /// Computed once per process and cached: `containerURL(forSecurityApplicationGroupIdentifier:)`
    /// talks to the sandbox/container subsystem and can be surprisingly slow,
    /// especially when the entitlement isn't cleanly provisioned (exactly the
    /// ambiguous state this app's App Group has been in). The container's
    /// location can't change while the app is running, so repeating this
    /// call from every SwiftUI view body re-render (several call sites did)
    /// was turning an occasional slow syscall into a per-render stall.
    static let cachedContainerURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier)

    var containerURL: URL? { Self.cachedContainerURL }
}
