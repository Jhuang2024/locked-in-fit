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
    /// background actor). No thread attribution: `Thread.isMainThread` is
    /// unavailable in async contexts (execution can hop threads across
    /// awaits, so the answer would be meaningless anyway); wall-clock time
    /// is what matters for a span like this, and the hang detector below
    /// covers main-thread responsiveness independently.
    @discardableResult
    static func measureAsync<T>(_ name: String, _ work: () async throws -> T) async rethrows -> T {
        let start = DispatchTime.now()
        let result = try await work()
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        let elapsedText = String(format: "%.1f", elapsedMs)
        logger.notice("[\(name, privacy: .public)] \(elapsedText, privacy: .public) ms (async)")
        return result
    }

    private static let tickLock = NSLock()
    nonisolated(unsafe) private static var tickCounts: [String: Int] = [:]

    /// Render-loop detector. Call from a view body (`let _ = PerfLog.tick("X.body")`)
    /// or a Binding getter. Bodies and getters normally evaluate a handful of
    /// times per interaction; if SwiftUI is stuck in an update feedback loop,
    /// whichever body/getter is cycling reaches hundreds of evaluations per
    /// second and this logs a fault every 100th call — so a frozen app names
    /// the looping view in the console, no debugger required.
    @discardableResult
    static func tick(_ name: String) -> Int {
        tickLock.lock()
        let count = (tickCounts[name] ?? 0) + 1
        tickCounts[name] = count
        tickLock.unlock()
        if count % 100 == 0 {
            logger.fault("RENDER LOOP? [\(name, privacy: .public)] evaluated \(count) times")
        }
        return count
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

/// Watches the main thread from a background queue and logs, loudly, the
/// moment it stops responding — and for how long, once it recovers.
///
/// `PerfLog.measure` can only report work it explicitly wraps, and only
/// after that work finishes. A freeze caused by an uninstrumented call (or
/// one that never returns) produces no log lines at all, which is exactly
/// what makes it unfindable from a log. This closes that gap: every 250ms a
/// watchdog queue pings the main queue; if the pong doesn't come back
/// within a second, a fault line is written immediately from the watchdog
/// thread (repeated every ~5s while stuck), so even a hang the user
/// force-quits out of leaves a timestamped trail right next to the last
/// normal event — which names the screen/action that froze.
final class MainThreadHangDetector: @unchecked Sendable {
    static let shared = MainThreadHangDetector()
    private static let logger = Logger(subsystem: "com.jerryhuang.LockedInFit", category: "Hang")

    private let watchdog = DispatchQueue(label: "com.jerryhuang.LockedInFit.hang-watchdog", qos: .userInitiated)
    private let lock = NSLock()
    private var started = false
    /// Set when a ping is dispatched to the main queue, cleared by the pong.
    private var pingSentAt: Date?
    /// How long the current hang had lasted when it was last reported, so
    /// an ongoing hang re-reports every ~5s instead of once or every tick.
    private var lastReportedSeconds = 0.0

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        watchdog.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.tick() }
    }

    private func tick() {
        lock.lock()
        if let sentAt = pingSentAt {
            let waited = Date().timeIntervalSince(sentAt)
            if waited >= 1.0, lastReportedSeconds == 0 || waited - lastReportedSeconds >= 5.0 {
                lastReportedSeconds = waited
                let text = String(format: "%.1f", waited)
                Self.logger.fault("MAIN THREAD HANG: unresponsive for \(text, privacy: .public)s and counting")
            }
            lock.unlock()
        } else {
            pingSentAt = Date()
            lock.unlock()
            DispatchQueue.main.async { [weak self] in self?.pong() }
        }
        watchdog.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.tick() }
    }

    private func pong() {
        lock.lock()
        let sentAt = pingSentAt
        let hadReported = lastReportedSeconds > 0
        pingSentAt = nil
        lastReportedSeconds = 0
        lock.unlock()
        if let sentAt, hadReported {
            let text = String(format: "%.1f", Date().timeIntervalSince(sentAt))
            Self.logger.fault("MAIN THREAD RECOVERED after \(text, privacy: .public)s")
        }
    }
}
