import Foundation
import OSLog

/// Shared Instruments intervals. Payloads never contain browsing URLs or titles.
enum BrowserPerformance {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Performance")
}

/// Waits for completion without making the deadline wait for uncancellable work.
/// The underlying task stays alive: timing out a waiter must not cancel shared activation.
@MainActor
enum TaskDeadline {
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

    static func wait(for task: Task<Void, Never>, timeout: Duration) async -> Bool {
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
