import Foundation

/// Locates the on-disk container the cross-app JSON bridge reads and writes.
/// Abstracted behind a protocol so `SharedContextStore` degrades to a no-op
/// instead of crashing when App Groups aren't provisioned for this build
/// (no signing team configured, or the App Group entitlement not granted).
protocol SharedContainerLocating {
    var containerURL: URL? { get }
}

/// Looks up the shared App Group container. Returns nil — never throws or
/// crashes — whenever the entitlement is missing or unprovisioned, which is
/// exactly the "App Groups unavailable" case the integration layer is built
/// to fall back through.
struct AppGroupContainerLocator: SharedContainerLocating {
    /// Shared identifier both LockedInFit and Social Climber register under
    /// their App Group capability.
    static let appGroupIdentifier = "group.com.jerry.personalOS"

    var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
    }
}
