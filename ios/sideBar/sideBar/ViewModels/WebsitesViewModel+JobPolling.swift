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
        jobPollingTasks[jobId]?.cancel()
        let token = UUID()
        jobPollingTaskTokens[jobId] = token
        jobPollingTasks[jobId] = Task { [weak self] in
            await self?.pollJobUntilComplete(
                jobId: jobId,
                pendingURL: pendingURL,
                previousSelectedId: previousSelectedId,
                shouldSelectOnCompletion: shouldSelectOnCompletion,
                token: token
            )
        }
    }

    func pollJobUntilComplete(
        jobId: String,
        pendingURL: URL,
        previousSelectedId: String?,
        shouldSelectOnCompletion: Bool = true,
        token: UUID
    ) async {
        defer {
            finishWebsiteJobPolling(jobId: jobId, token: token)
        }
        let startTime = Date()
        var attemptIndex = 0
        while Date().timeIntervalSince(startTime) < Self.jobPollMaxDuration {
            let interval = attemptIndex < Self.jobPollIntervals.count
                ? Self.jobPollIntervals[attemptIndex]
                : Self.jobPollIntervals.last ?? 60
            try? await Task.sleep(for: .seconds(interval))
            attemptIndex += 1
            guard !Task.isCancelled else { return }
            guard allowsFallbackPolling(.websites, true) else { return }
            let isTerminal = await refreshWebsiteJobStatus(
                jobId: jobId,
                pendingURL: pendingURL,
                previousSelectedId: previousSelectedId,
                shouldSelectOnCompletion: shouldSelectOnCompletion
            )
            if isTerminal {
                return
            }
        }
        endWebsiteSave()
        failWebsiteSave(
            previousSelectedId: previousSelectedId,
            pendingURL: pendingURL,
            message: "Save timed out"
        )
        clearWebsiteJobPolling(jobId: jobId)
    }

    @discardableResult
    func refreshWebsiteJobStatus(
        jobId: String,
        pendingURL: URL,
        previousSelectedId: String?,
        shouldSelectOnCompletion: Bool
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
                clearWebsiteJobPolling(jobId: jobId)
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
                clearWebsiteJobPolling(jobId: jobId)
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
                clearWebsiteJobPolling(jobId: jobId)
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
}
