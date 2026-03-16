import Foundation
import sideBarShared

@MainActor
extension WebsitesViewModel {
    /// Force-refresh after a Share Extension save. Always bypasses the rate
    /// limit because the user explicitly saved a new item and expects it to
    /// appear immediately. Updates lastForcedLoadAt so the next lifecycle-
    /// triggered load(force: true) is still suppressed for the cooldown window.
    public func refreshFromExtension() async {
        lastForcedLoadAt = Date()
        errorMessage = nil
        do {
            try await store.loadList(force: true)
        } catch {
            if items.isEmpty {
                errorMessage = ErrorMapping.message(for: error)
            }
        }
    }

    public func showPendingFromExtension(url: String) {
        guard let normalized = WebsiteURLValidator.normalizedCandidate(url) else {
            return
        }
        _ = upsertPendingWebsite(from: normalized, source: .queuedShare)
    }

    public func syncPendingWebsitesFromQueuedShares(
        _ queuedItems: [PendingShareItem],
        readingQueueItemId: UUID? = nil
    ) {
        syncQueuedPendingWebsites(with: queuedItems, readingQueueItemId: readingQueueItemId)
    }
}
