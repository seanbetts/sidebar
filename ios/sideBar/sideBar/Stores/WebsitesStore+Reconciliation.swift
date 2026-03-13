import Foundation

final class WebsitesStoreReconciliationState {
    var expirations: [String: Date] = [:]
    let window: TimeInterval

    init(window: TimeInterval) {
        self.window = window
    }
}

extension WebsitesStore {
    func preserveLocallyInsertedWebsite(id: String) {
        reconciliationState.expirations[id] = Date()
            .addingTimeInterval(reconciliationState.window)
    }

    func reconcileLocallyInsertedActiveItems(_ incoming: [WebsiteItem], current: [WebsiteItem]) -> [WebsiteItem] {
        pruneExpiredLocallyInsertedWebsites()
        guard !reconciliationState.expirations.isEmpty else {
            return incoming
        }

        let incomingIds = Set(incoming.map(\.id))
        for id in incomingIds {
            reconciliationState.expirations.removeValue(forKey: id)
        }

        let preserved = current.filter { item in
            item.archived == false
                && incomingIds.contains(item.id) == false
                && reconciliationState.expirations[item.id] != nil
        }
        guard !preserved.isEmpty else {
            return incoming
        }
        return mergeReconciledActiveItems(incoming: incoming, preserved: preserved)
    }

    func mergeReconciledActiveItems(incoming: [WebsiteItem], preserved: [WebsiteItem]) -> [WebsiteItem] {
        var merged = incoming
        let pinnedInsertIndex = incoming.prefix { $0.pinned }.count
        var activeInsertIndex = pinnedInsertIndex

        let preservedPinned = preserved.filter(\.pinned).sorted { lhs, rhs in
            let leftOrder = lhs.pinnedOrder ?? Int.max
            let rightOrder = rhs.pinnedOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            let leftDate = DateParsing.parseISO8601(lhs.updatedAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.updatedAt) ?? .distantPast
            return leftDate > rightDate
        }
        for item in preservedPinned where merged.contains(where: { $0.id == item.id }) == false {
            merged.insert(item, at: min(activeInsertIndex, merged.count))
            activeInsertIndex += 1
        }

        let preservedUnpinned = preserved.filter { !$0.pinned }
        for item in preservedUnpinned where merged.contains(where: { $0.id == item.id }) == false {
            merged.insert(item, at: min(activeInsertIndex, merged.count))
            activeInsertIndex += 1
        }
        return merged
    }

    func pruneExpiredLocallyInsertedWebsites(now: Date = Date()) {
        reconciliationState.expirations = reconciliationState.expirations.filter { $0.value > now }
    }
}
