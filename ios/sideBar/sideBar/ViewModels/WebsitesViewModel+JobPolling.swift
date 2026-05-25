import Foundation
import OSLog

@MainActor
extension WebsitesViewModel {

    // MARK: - Job Polling

    private static let jobPollIntervals: [TimeInterval] = [2, 3, 5, 8, 13, 20, 30, 30]
    private static let jobPollMaxDuration: TimeInterval = 300

    func startWebsiteJobPollingIfAllowed(
        jobId: String,
        pendingURL: URL,
        previousSelectedId: String?,
        shouldSelectOnCompletion: Bool
    ) {
        guard allowsFallbackPolling(.websites, true) else { return }
        cancelWebsiteJobPolling(jobId: jobId)
        let token = UUID()
        let jobPollingSleep = jobPollingSleep
        jobPollingTaskTokens[jobId] = token
        jobPollingTasks[jobId] = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.finishWebsiteJobPolling(jobId: jobId, token: token)
                }
            }
            let startTime = Date()
            var attemptIndex = 0
            while Date().timeIntervalSince(startTime) < Self.jobPollMaxDuration {
                let interval = attemptIndex < Self.jobPollIntervals.count
                    ? Self.jobPollIntervals[attemptIndex]
                    : Self.jobPollIntervals.last ?? 60
                do {
                    try await jobPollingSleep(UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                attemptIndex += 1
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard self.allowsFallbackPolling(.websites, true) else { return }
                let isTerminal = await self.refreshWebsiteJobStatus(
                    jobId: jobId,
                    pendingURL: pendingURL,
                    previousSelectedId: previousSelectedId,
                    shouldSelectOnCompletion: shouldSelectOnCompletion,
                    pollingToken: token
                )
                if isTerminal {
                    return
                }
            }
            guard let self else { return }
            self.endWebsiteSave()
            self.failWebsiteSave(
                previousSelectedId: previousSelectedId,
                pendingURL: pendingURL,
                message: "Save timed out"
            )
        }
    }

    @discardableResult
    func refreshWebsiteJobStatus(
        jobId: String,
        pendingURL: URL,
        previousSelectedId: String?,
        shouldSelectOnCompletion: Bool,
        pollingToken: UUID? = nil
    ) async -> Bool {
        guard allowsFallbackPolling(.websites, true) else {
            return false
        }
        do {
            let response = try await api.jobStatus(id: jobId)
            switch response.status {
            case "completed":
                if let website = response.website {
                    applySavedWebsite(
                        website,
                        pendingURL: pendingURL,
                        shouldSelectOnCompletion: shouldSelectOnCompletion
                    )
                } else {
                    removePendingWebsite(for: pendingURL.absoluteString)
                }
                endWebsiteSave()
                completeWebsiteJobPolling(jobId: jobId, pollingToken: pollingToken)
                await completeWebsiteJobProgress(
                    jobId: jobId,
                    status: response.status,
                    entityId: response.website?.id,
                    requiresDetailRefresh: shouldSelectOnCompletion && response.website != nil
                )
                return true
            case "canceled":
                endWebsiteSave()
                removePendingWebsite(for: pendingURL.absoluteString)
                completeWebsiteJobPolling(jobId: jobId, pollingToken: pollingToken)
                await completeWebsiteJobProgress(
                    jobId: jobId,
                    status: response.status,
                    entityId: nil,
                    requiresDetailRefresh: false
                )
                return true
            case "failed", "stalled":
                let message = response.error?.message ?? "Save failed"
                endWebsiteSave()
                failWebsiteSave(
                    previousSelectedId: previousSelectedId,
                    pendingURL: pendingURL,
                    message: message
                )
                completeWebsiteJobPolling(jobId: jobId, pollingToken: pollingToken)
                await completeWebsiteJobProgress(
                    jobId: jobId,
                    status: response.status,
                    entityId: nil,
                    requiresDetailRefresh: false
                )
                return true
            case "processing":
                updatePendingWebsiteStatus(for: pendingURL.absoluteString, status: .reading)
                return false
            case "retrying":
                updatePendingWebsiteStatus(for: pendingURL.absoluteString, status: .retrying)
                return false
            case "queued":
                updatePendingWebsiteStatus(for: pendingURL.absoluteString, status: .queued)
                return false
            default:
                return false
            }
        } catch {
            return false
        }
    }

    func cancelWebsiteJobPolling(jobId: String) {
        jobPollingTasks[jobId]?.cancel()
        clearWebsiteJobPolling(jobId: jobId)
    }

    func clearWebsiteJobPolling(jobId: String) {
        jobPollingTasks.removeValue(forKey: jobId)
        jobPollingTaskTokens.removeValue(forKey: jobId)
    }

    func completeWebsiteJobProgress(
        jobId: String,
        status: String,
        entityId: String?,
        requiresDetailRefresh: Bool
    ) async {
        _ = await jobProgressCoordinator.applyRealtimeStatus(
            jobId: jobId,
            status: AsyncJobStatus(rawValue: status),
            userMessage: nil
        )
        await scheduleWebsiteJobTerminalRefresh(
            entityId: entityId,
            requiresDetailRefresh: requiresDetailRefresh
        )
    }

    private func finishWebsiteJobPolling(jobId: String, token: UUID) {
        guard jobPollingTaskTokens[jobId] == token else { return }
        clearWebsiteJobPolling(jobId: jobId)
    }

    private func completeWebsiteJobPolling(jobId: String, pollingToken: UUID?) {
        if let pollingToken {
            finishWebsiteJobPolling(jobId: jobId, token: pollingToken)
        } else {
            cancelWebsiteJobPolling(jobId: jobId)
        }
    }
}
