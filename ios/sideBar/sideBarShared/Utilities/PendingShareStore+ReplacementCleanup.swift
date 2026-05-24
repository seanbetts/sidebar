import Foundation

extension PendingShareStore {
    public func replaceAllCleaningRemovedStagedFiles(_ newItems: [PendingShareItem]) -> Bool {
        withAccessLock {
            let newReferences = Set(newItems.compactMap(stagedReferenceKey))
            let oldItems = loadAll()
            let removedItems = oldItems.filter { oldItem in
                guard let oldReference = stagedReferenceKey(for: oldItem) else { return false }
                return newReferences.contains(oldReference) == false
            }
            let cleanup = stagedCleanupResults(for: removedItems)
            let failedIds = Set(cleanup.failed.map(\.id))
            let retainedFailedItems = oldItems.filter { failedIds.contains($0.id) }
            let retainedFailedItemIds = Set(retainedFailedItems.map(\.id))
            let retainedNewItems = newItems.filter { retainedFailedItemIds.contains($0.id) == false }
            writeMetadata(retainedFailedItems + retainedNewItems)
            return cleanup.failed.isEmpty
        }
    }

    private func stagedFilePath(for item: PendingShareItem) -> String? {
        guard item.kind == .file || item.kind == .image else { return nil }
        return item.filePath
    }

    private func stagedReferenceKey(for item: PendingShareItem) -> String? {
        stagedFilePath(for: item)
    }
}
