import Foundation

@MainActor
extension WebsitesViewModel {
    public var pendingWebsite: PendingWebsiteItem? {
        get { pendingWebsites.first }
        set {
            if let newValue {
                pendingWebsites = [newValue]
            } else {
                pendingWebsites.removeAll()
            }
        }
    }

    var detailLoadingMessage: String {
        if let selectedWebsiteId,
           let selectedPending = pendingWebsites.first(where: { $0.id == selectedWebsiteId }) {
            return selectedPending.progressMessage
        }
        return pendingWebsites.first?.progressMessage ?? "Reading..."
    }

    var hasCachedSelectedWebsiteDetail: Bool {
        guard let selectedWebsiteId else { return false }
        return store.hasCachedDetail(id: selectedWebsiteId)
    }
}
