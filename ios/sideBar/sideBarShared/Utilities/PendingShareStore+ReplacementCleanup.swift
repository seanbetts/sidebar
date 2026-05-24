import Foundation

extension PendingShareStore {
    public func replaceAllCleaningRemovedStagedFiles(_ newItems: [PendingShareItem]) -> Bool {
        withAccessLock {
            let newReferences = Set(newItems.compactMap(stagedReferenceKey))
            let removedItems = loadAll().filter { oldItem in
                guard let oldReference = stagedReferenceKey(for: oldItem) else { return false }
                return newReferences.contains(oldReference) == false
            }
            for item in removedItems {
                guard removeStagedFileIfPresent(for: item) else { return false }
            }
            writeMetadata(newItems)
            return true
        }
    }

    private func stagedFilePath(for item: PendingShareItem) -> String? {
        guard item.kind == .file || item.kind == .image else { return nil }
        return item.filePath
    }

    private func stagedReferenceKey(for item: PendingShareItem) -> String? {
        guard let filePath = stagedFilePath(for: item) else { return nil }
        return "\(item.id.uuidString)|\(filePath)"
    }
}
