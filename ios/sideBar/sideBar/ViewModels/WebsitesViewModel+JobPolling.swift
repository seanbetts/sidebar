import Foundation
import OSLog

@MainActor
extension WebsitesViewModel {

    // MARK: - Job Polling

    private static let jobPollIntervals: [TimeInterval] = [2, 3, 5, 8, 13, 20, 30, 30]
    private static let jobPollMaxDuration: TimeInterval = 300

    func pollJobUntilComplete(
        jobId: String,
        pendingURL: URL,
        previousSelectedId: String?,
        shouldSelectOnCompletion: Bool = true
    ) async {
        let startTime = Date()
        var attemptIndex = 0
        while Date().timeIntervalSince(startTime) < Self.jobPollMaxDuration {
            let interval = attemptIndex < Self.jobPollIntervals.count
                ? Self.jobPollIntervals[attemptIndex]
                : Self.jobPollIntervals.last ?? 60
            try? await Task.sleep(for: .seconds(interval))
            attemptIndex += 1
            guard !Task.isCancelled else { return }
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
        jobPollingTasks.removeValue(forKey: jobId)
    }

    @discardableResult
    func refreshWebsiteJobStatus(
        jobId: String,
        pendingURL: URL,
        previousSelectedId: String?,
        shouldSelectOnCompletion: Bool
    ) async -> Bool {
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
                jobPollingTasks.removeValue(forKey: jobId)
                return true
            case "canceled":
                endWebsiteSave()
                removePendingWebsite(for: pendingURL.absoluteString)
                jobPollingTasks.removeValue(forKey: jobId)
                return true
            case "failed", "stalled":
                let message = response.error?.message ?? "Save failed"
                endWebsiteSave()
                failWebsiteSave(
                    previousSelectedId: previousSelectedId,
                    pendingURL: pendingURL,
                    message: message
                )
                jobPollingTasks.removeValue(forKey: jobId)
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
}
