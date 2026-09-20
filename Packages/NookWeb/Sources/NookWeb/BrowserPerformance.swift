// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import Foundation
import OSLog

/// Shared Instruments intervals. Payloads never contain browsing URLs or titles.
public enum BrowserPerformance {
    public static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Performance")
}

/// Launch to first paint, the headline startup number. Measured from the kernel's process start
/// time rather than from `main()`, so dyld and pre-main work are included: those are what binary
/// size moves, and leaving them out would flatter every change to it.
@MainActor
public enum LaunchMetrics {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Performance")
    private static var reported = false

    /// Seconds since this process was forked, or nil if the kernel would not say.
    public static func elapsedSinceProcessStart() -> TimeInterval? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let status = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard status == 0 else { return nil }
        let started = info.kp_proc.p_starttime
        let startSeconds = Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
        return Date().timeIntervalSince1970 - startSeconds
    }

    /// Call when the first page of the session commits: the moment something is on screen.
    /// Only the first call in a process reports; later navigations are not launches.
    public static func markFirstPaint() {
        guard !reported else { return }
        reported = true
        guard let elapsed = elapsedSinceProcessStart() else { return }
        log.notice("launch to first paint: \(elapsed * 1000, format: .fixed(precision: 0), privacy: .public)ms")
    }
}

/// Waits for completion without making the deadline wait for uncancellable work.
/// The underlying task stays alive: timing out a waiter must not cancel shared activation.
@MainActor
public enum TaskDeadline {
    private final class Gate {
        var continuation: CheckedContinuation<Bool, Never>?
        var timer: Task<Void, Never>?

        func finish(_ completed: Bool) {
            guard let continuation else { return }
            self.continuation = nil
            timer?.cancel()
            timer = nil
            continuation.resume(returning: completed)
        }
    }

    public static func wait(for task: Task<Void, Never>, timeout: Duration) async -> Bool {
        let gate = Gate()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            return await withCheckedContinuation { continuation in
                gate.continuation = continuation
                gate.timer = Task {
                    do { try await Task.sleep(for: timeout) } catch { return }
                    gate.finish(false)
                }
                Task {
                    await task.value
                    gate.finish(true)
                }
            }
        } onCancel: {
            Task { @MainActor in gate.finish(false) }
        }
    }
}
