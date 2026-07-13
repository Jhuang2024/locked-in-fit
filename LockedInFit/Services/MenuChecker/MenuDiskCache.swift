import Foundation

/// On-disk cache of fetched menus, so reconstructing a restaurant's menu costs at
/// most one AI call per TTL, even across app launches. The in-memory
/// `MenuCheckerCache` only survives the current session; this backs it with the
/// Caches directory (which the OS may evict under storage pressure, which is
/// fine; a miss just re-fetches). Keyed by a stable hash of the restaurant id so
/// filenames are fixed-length and launch-stable (Swift's `hashValue` is NOT;
/// it's per-process randomised, so we hash deterministically here).
enum MenuDiskCache {
    private struct Payload: Codable {
        var fetchedAt: Date
        var items: [MenuItem]
    }

    private static let directory: URL? = {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("MenuChecker", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Deterministic FNV-1a 64-bit hash → fixed-length, launch-stable filename.
    private static func stableKey(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private static func fileURL(for restaurantID: String) -> URL? {
        directory?.appendingPathComponent("\(stableKey(restaurantID)).json")
    }

    /// Load a cached menu if present and younger than `maxAge`.
    static func load(restaurantID: String, maxAge: TimeInterval) -> (items: [MenuItem], fetchedAt: Date)? {
        guard let url = fileURL(for: restaurantID),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        guard Date().timeIntervalSince(payload.fetchedAt) <= maxAge, !payload.items.isEmpty else { return nil }
        return (payload.items, payload.fetchedAt)
    }

    static func store(_ items: [MenuItem], restaurantID: String) {
        guard !items.isEmpty, let url = fileURL(for: restaurantID) else { return }
        let payload = Payload(fetchedAt: .now, items: items)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func remove(restaurantID: String) {
        guard let url = fileURL(for: restaurantID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
