import Foundation
import os

/// Lightweight instrumentation added specifically so a class of bug (silent
/// main-thread stalls from persistence/backup/HealthKit work) is provable in
/// testing instead of invisible until a user reports a freeze. Safe to leave
/// in permanently: logs only to the unified logging system (Console.app /
/// Xcode's console via the "Perf" category), never written to disk, and
/// negligible overhead outside of active tracing.
enum PerfLog {
    private static let logger = Logger(subsystem: "com.jerryhuang.LockedInFit", category: "Perf")

    static func event(_ name: String) {
        logger.notice("event: \(name, privacy: .public)")
    }

    /// Measures synchronous `work` and logs how long it took and which
    /// thread it ran on. Anything over 250ms on the main thread logs as a
    /// fault, loud and unmistakable in Console, since that's exactly the
    /// class of call that causes a visible freeze.
    @discardableResult
    static func measure<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        let isMain = Thread.isMainThread
        let start = DispatchTime.now()
        let result = try work()
        report(name, start: start, isMain: isMain)
        return result
    }

    /// Same as `measure`, for work that awaits (e.g. hopping onto a
    /// background actor).
    @discardableResult
    static func measureAsync<T>(_ name: String, _ work: () async throws -> T) async rethrows -> T {
        let isMain = Thread.isMainThread
        let start = DispatchTime.now()
        let result = try await work()
        report(name, start: start, isMain: isMain)
        return result
    }

    private static func report(_ name: String, start: DispatchTime, isMain: Bool) {
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        let elapsedText = String(format: "%.1f", elapsedMs)
        if isMain && elapsedMs > 250 {
            logger.fault("SLOW MAIN THREAD [\(name, privacy: .public)]: \(elapsedText, privacy: .public) ms")
        } else {
            logger.notice("[\(name, privacy: .public)] \(elapsedText, privacy: .public) ms (main=\(isMain, privacy: .public))")
        }
    }
}
