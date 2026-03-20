import Foundation

@MainActor
extension WebsitesViewModel {

    // MARK: - Job Polling

    private static let jobPollIntervals: [TimeInterval] = [10, 15, 20, 30, 45, 60, 60]
    private static let jobPollMaxDuration: TimeInterval = 300

    func pollJobUntilComplete(
        jobId: String,
        pendingURL: URL,
        previousSelectedId: String?
    ) async {
        let startTime = Date()
        var attemptIndex = 0
        while Date().timeIntervalSince(startTime) < Self.jobPollMaxDuration {
            guard hasPendingWebsite(for: pendingURL) else { return }
            let interval = attemptIndex < Self.jobPollIntervals.count
                ? Self.jobPollIntervals[attemptIndex]
                : Self.jobPollIntervals.last ?? 60
            try? await Task.sleep(for: .seconds(interval))
            attemptIndex += 1
            guard !Task.isCancelled else { return }
            do {
                let response = try await api.jobStatus(id: jobId)
                switch response.status {
                case "completed":
                    if let website = response.website {
                        applySavedWebsite(website, pendingURL: pendingURL)
                    }
                    jobPollingTasks.removeValue(forKey: jobId)
                    return
                case "failed":
                    let message = response.error?.message ?? "Save failed"
                    failWebsiteSave(
                        previousSelectedId: previousSelectedId,
                        pendingURL: pendingURL,
                        message: message
                    )
                    jobPollingTasks.removeValue(forKey: jobId)
                    return
                default:
                    continue
                }
            } catch {
                continue
            }
        }
        failWebsiteSave(
            previousSelectedId: previousSelectedId,
            pendingURL: pendingURL,
            message: "Save timed out"
        )
        jobPollingTasks.removeValue(forKey: jobId)
    }

    func didReceiveWebsiteJobUpdate(
        jobId: String,
        status: String?,
        websiteId: String?,
        errorMessage: String?
    ) {
        guard let pending = pendingWebsiteByJobId(jobId) else { return }
        guard let resolvedStatus = status else { return }
        switch resolvedStatus {
        case "completed":
            jobPollingTasks[jobId]?.cancel()
            jobPollingTasks.removeValue(forKey: jobId)
            if let websiteId {
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let detail = try await self.api.get(id: websiteId)
                        let pendingURL = URL(string: pending.url) ?? URL(string: "https://invalid")!
                        self.applySavedWebsite(detail, pendingURL: pendingURL)
                    } catch {
                        self.logger.error("Failed to fetch completed website \(websiteId): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        case "failed":
            jobPollingTasks[jobId]?.cancel()
            jobPollingTasks.removeValue(forKey: jobId)
            let pendingURL = URL(string: pending.url) ?? URL(string: "https://invalid")!
            let message = errorMessage ?? "Save failed"
            failWebsiteSave(
                previousSelectedId: nil,
                pendingURL: pendingURL,
                message: message
            )
        default:
            break
        }
    }
}
