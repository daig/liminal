import Foundation
import os

/// Lightweight `os_signpost` wrapper for performance instrumentation.
///
/// Intervals are emitted on one shared `OSSignposter`, so intervals nested in
/// the call stack nest in Instruments — a scenario bracket (e.g. `keystroke`)
/// shows its component chokepoints (`parse`, `highlight`) underneath it.
///
/// Profile with the **os_signpost** instrument filtered to subsystem
/// `dev.liminal.perf` (add Time Profiler / Core Animation for the AppKit layer).
/// Signposts are near-zero-overhead when no tool is recording, so they stay
/// compiled in. Set `LIMINAL_PERF_LOG=1` in the environment to also mirror each
/// interval's duration to the unified log (read via
/// `log stream --predicate 'subsystem == "dev.liminal.perf"'`).
enum PerfSignpost {
    static let subsystem = "dev.liminal.perf"
    static let signposter = OSSignposter(subsystem: subsystem, category: "Perf")

    static let logToConsole = ProcessInfo.processInfo.environment["LIMINAL_PERF_LOG"] == "1"
    private static let logger = Logger(subsystem: subsystem, category: "Perf")

    /// Time a synchronous region. `message` carries metadata (byte counts,
    /// reuse hits, span counts) into the Instruments detail row.
    @discardableResult
    @inline(__always)
    static func interval<R>(
        _ name: StaticString,
        _ message: @autoclosure () -> String = "",
        _ body: () throws -> R
    ) rethrows -> R {
        let msg = message()
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID(), "\(msg, privacy: .public)")
        let start: ContinuousClock.Instant? = logToConsole ? ContinuousClock().now : nil
        defer {
            signposter.endInterval(name, state)
            if let start {
                let dur = (ContinuousClock().now - start).description
                logger.info("\(String(describing: name), privacy: .public) \(dur, privacy: .public) \(msg, privacy: .public)")
            }
        }
        return try body()
    }

    /// Begin an interval that spans an async boundary (e.g. cold-boot, which
    /// crosses SwiftUI's `makeNSView` dispatch). Pair with `end`.
    static func begin(_ name: StaticString, _ message: @autoclosure () -> String = "") -> OSSignpostIntervalState {
        let msg = message()
        return signposter.beginInterval(name, id: signposter.makeSignpostID(), "\(msg, privacy: .public)")
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: @autoclosure () -> String = "") {
        let msg = message()
        signposter.endInterval(name, state, "\(msg, privacy: .public)")
    }
}
