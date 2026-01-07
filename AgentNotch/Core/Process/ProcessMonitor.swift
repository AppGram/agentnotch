import Foundation

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published private(set) var restartAttempts: Int = 0
    @Published private(set) var lastCrashTime: Date?

    private let maxRestartAttempts: Int
    private let autoRestart: Bool
    private var restartTask: Task<Void, Never>?

    var onRestartNeeded: (() async throws -> Void)?

    init(maxRestartAttempts: Int = 5, autoRestart: Bool = true) {
        self.maxRestartAttempts = maxRestartAttempts
        self.autoRestart = autoRestart
    }

    func handleTermination(status: Int32) async {
        // Clean exit (status 0) - don't restart
        if status == 0 {
            resetAttempts()
            return
        }

        lastCrashTime = Date()

        guard autoRestart else { return }
        guard restartAttempts < maxRestartAttempts else {
            // Give up - too many attempts
            return
        }

        restartAttempts += 1
        let backoffSeconds = pow(2.0, Double(restartAttempts - 1)) // 1, 2, 4, 8, 16 seconds

        restartTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                try await onRestartNeeded?()
            } catch {
                // Restart failed - will try again on next termination
            }
        }
    }

    func resetAttempts() {
        restartAttempts = 0
        lastCrashTime = nil
        restartTask?.cancel()
        restartTask = nil
    }

    func cancelPendingRestart() {
        restartTask?.cancel()
        restartTask = nil
    }

    var canRestart: Bool {
        restartAttempts < maxRestartAttempts
    }

    var backoffTime: TimeInterval {
        pow(2.0, Double(restartAttempts))
    }
}
