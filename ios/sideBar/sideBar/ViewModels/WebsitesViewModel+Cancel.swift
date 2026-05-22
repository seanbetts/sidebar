import Foundation

@MainActor
extension WebsitesViewModel {
    public func canCancelWebsiteSave() -> Bool {
        cancelablePendingWebsite != nil
    }

    public func cancelWebsiteSave() async {
        guard let pending = cancelablePendingWebsite,
              pending.jobId != nil else { return }

        await cancelPendingWebsite(id: pending.id)
    }

    public func cancelPendingWebsite(id: String) async {
        guard let pending = pendingWebsite(id: id),
              let jobId = pending.jobId else { return }

        do {
            try await api.cancel(jobId: jobId)
        } catch {
            toastCenter.show(message: "Failed to cancel website save")
            return
        }

        jobPollingTasks[jobId]?.cancel()
        clearWebsiteJobPolling(jobId: jobId)
        removePendingWebsite(id: pending.id)
        if selectedWebsiteId == pending.id {
            selectedWebsiteId = nil
        }
        saveErrorMessage = nil
        endWebsiteSave()
    }

    var cancelablePendingWebsite: PendingWebsiteItem? {
        if let selectedWebsiteId,
           let selectedPending = pendingWebsites.first(where: {
               $0.id == selectedWebsiteId && $0.canCancel
           }) {
            return selectedPending
        }
        return pendingWebsites.first { $0.canCancel }
    }
}
