import Foundation

@MainActor
final class AsyncJobProgressCoordinator {
    private var jobsById: [String: AsyncJobDescriptor] = [:]

    func register(_ descriptor: AsyncJobDescriptor) {
        jobsById[descriptor.jobId] = descriptor
    }

    func cancel(jobId: String) {
        jobsById.removeValue(forKey: jobId)
    }

    func hasActiveJob(jobId: String) -> Bool {
        jobsById[jobId] != nil
    }

    func shouldPoll(jobId: String, health: SyncHealthState) -> Bool {
        jobsById[jobId] != nil && health.allowsFallbackPolling
    }

    func descriptor(jobId: String) -> AsyncJobDescriptor? {
        jobsById[jobId]
    }

    func applyRealtimeStatus(
        jobId: String,
        status: AsyncJobStatus,
        userMessage: String?
    ) async -> AsyncJobProgressResult {
        guard let descriptor = jobsById[jobId] else {
            return .unknownJob
        }
        let normalized = status.normalized
        if descriptor.terminalStatuses.contains(normalized) {
            jobsById.removeValue(forKey: jobId)
            return .terminal(status: normalized, userMessage: userMessage)
        }
        return .active(status: normalized)
    }
}
