import Foundation
import sideBarShared

extension WebsitesViewModel {
    public func reorderPinnedWebsites(ids: [String]) async -> Bool {
        let previousOrder = store.pinnedWebsiteOrder()
        guard ids.count == previousOrder.count, Set(ids) == Set(previousOrder) else {
            return false
        }
        do {
            try await store.enqueuePinnedOrder(ids: ids)
            return true
        } catch WriteQueueError.queueFull {
            errorMessage = "Sync queue full. Review pending changes."
            return false
        } catch {
            errorMessage = "Failed to queue pinned order"
            return false
        }
    }
}
