import Foundation
import sideBarShared

extension WebsitesViewModel {
    public func reorderPinnedWebsites(ids: [String]) async -> Bool {
        guard networkStatus.isNetworkAvailable, !networkStatus.isOffline else {
            return false
        }
        let previousOrder = store.pinnedWebsiteOrder()
        guard ids.count == previousOrder.count, Set(ids) == Set(previousOrder) else {
            return false
        }
        store.applyPinnedOrder(ids)
        do {
            try await api.updatePinnedOrder(ids: ids)
            return true
        } catch {
            store.applyPinnedOrder(previousOrder)
            errorMessage = "Failed to reorder pinned websites"
            return false
        }
    }
}
