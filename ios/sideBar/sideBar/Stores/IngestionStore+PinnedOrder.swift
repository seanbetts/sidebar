import Foundation
import sideBarShared

extension IngestionStore {
    func pinnedFileOrder() -> [String] {
        items
            .filter { $0.file.pinned == true && $0.file.deletedAt == nil }
            .sorted(by: sortPinnedFiles)
            .map(\.file.id)
    }

    func applyPinnedOrder(_ ids: [String]) {
        guard !items.isEmpty else { return }

        let pinnedOrderLookup = ids.enumerated().reduce(into: [String: Int]()) { result, pair in
            result[pair.element] = pair.offset
        }

        remoteItems = remoteItems.map { updatePinnedOrder(for: $0, pinnedOrderLookup: pinnedOrderLookup) }
        localItems = localItems.mapValues { updatePinnedOrder(for: $0, pinnedOrderLookup: pinnedOrderLookup) }
        localUploadRecords = localUploadRecords.mapValues { record in
            LocalUploadRecord(
                item: updatePinnedOrder(for: record.item, pinnedOrderLookup: pinnedOrderLookup),
                bookmarkData: record.bookmarkData
            )
        }

        if let activeMeta, let pinnedOrder = pinnedOrderLookup[activeMeta.file.id] {
            self.activeMeta = IngestionMetaResponse(
                file: updatePinnedOrder(for: activeMeta.file, pinnedOrder: pinnedOrder),
                job: activeMeta.job,
                derivatives: activeMeta.derivatives,
                recommendedViewer: activeMeta.recommendedViewer
            )
        }

        items = mergeItems(remoteItems)
        persistListCache()
        persistLocalUploads()
        updateWidgetData()
    }

    private func updatePinnedOrder(
        for item: IngestionListItem,
        pinnedOrderLookup: [String: Int]
    ) -> IngestionListItem {
        guard item.file.pinned == true, let pinnedOrder = pinnedOrderLookup[item.file.id] else {
            return item
        }
        return IngestionListItem(
            file: updatePinnedOrder(for: item.file, pinnedOrder: pinnedOrder),
            job: item.job,
            recommendedViewer: item.recommendedViewer
        )
    }

    private func updatePinnedOrder(for file: IngestedFileMeta, pinnedOrder: Int) -> IngestedFileMeta {
        IngestedFileMeta(
            id: file.id,
            filenameOriginal: file.filenameOriginal,
            path: file.path,
            mimeOriginal: file.mimeOriginal,
            sizeBytes: file.sizeBytes,
            sha256: file.sha256,
            pinned: file.pinned,
            pinnedOrder: pinnedOrder,
            category: file.category,
            sourceUrl: file.sourceUrl,
            sourceMetadata: file.sourceMetadata,
            createdAt: file.createdAt,
            updatedAt: file.updatedAt,
            deletedAt: file.deletedAt
        )
    }

    private func sortPinnedFiles(_ lhs: IngestionListItem, _ rhs: IngestionListItem) -> Bool {
        let leftOrder = lhs.file.pinnedOrder ?? Int.max
        let rightOrder = rhs.file.pinnedOrder ?? Int.max
        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        return lhs.file.id < rhs.file.id
    }
}
