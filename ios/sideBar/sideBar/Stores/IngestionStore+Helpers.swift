import Foundation
import sideBarShared

// MARK: - Helpers

extension IngestionStore {
    func refreshList() async {
        guard !isRefreshingList else {
            return
        }
        isRefreshingList = true
        defer { isRefreshingList = false }
        do {
            let response = try await api.list()
            isOffline = false
            applyListUpdate(response.items, persist: true)
        } catch {
            isOffline = true
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    func refreshMeta(fileId: String) async {
        guard !refreshingMetaIds.contains(fileId) else {
            return
        }
        refreshingMetaIds.insert(fileId)
        defer { refreshingMetaIds.remove(fileId) }
        do {
            let response = try await api.getMeta(fileId: fileId)
            isOffline = false
            applyMetaUpdate(response, persist: true)
        } catch {
            isOffline = true
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    func applyListUpdate(_ incoming: [IngestionListItem], persist: Bool) {
        guard shouldUpdateList(incoming) else {
            return
        }
        remoteItems = incoming
        items = mergeItems(incoming)
        if persist {
            persistListCache()
            indexFilesInSpotlight(incoming)
        }
        updateWidgetData()
    }

    private func indexFilesInSpotlight(_ items: [IngestionListItem]) {
        guard let indexer = spotlightIndexer else { return }
        let spotlightFiles = items.compactMap { item -> SpotlightFile? in
            guard item.file.deletedAt == nil else { return nil }
            return SpotlightFile(
                id: item.file.id,
                filename: item.file.filenameOriginal,
                category: item.file.category,
                mimeType: item.file.mimeOriginal,
                sizeBytes: item.file.sizeBytes,
                createdAt: DateParsing.parseISO8601(item.file.createdAt)
            )
        }
        Task {
            await indexer.indexFiles(spotlightFiles)
        }
    }

    func removeFileFromSpotlight(id: String) {
        guard let indexer = spotlightIndexer else { return }
        Task {
            await indexer.removeFile(id: id)
        }
    }

    func updateWidgetData() {
        let pinnedFiles = items
            .filter { $0.file.pinned == true && $0.file.deletedAt == nil }
            .sorted { ($0.file.pinnedOrder ?? Int.max) < ($1.file.pinnedOrder ?? Int.max) }
            .map { WidgetFile(from: $0) }
        let displayFiles = Array(pinnedFiles.prefix(10))
        let data = WidgetFileData(files: displayFiles, totalCount: pinnedFiles.count)
        WidgetDataManager.shared.store(data, for: .files)
    }

    func shouldUpdateList(_ incoming: [IngestionListItem]) -> Bool {
        guard remoteItems.count == incoming.count else {
            return true
        }
        let existing = Dictionary(uniqueKeysWithValues: remoteItems.map { ($0.file.id, $0) })
        for item in incoming {
            guard let current = existing[item.file.id] else {
                return true
            }
            if current.job.updatedAt != item.job.updatedAt
                || current.job.status != item.job.status
                || current.job.stage != item.job.stage
                || current.file.pinned != item.file.pinned
                || current.file.pinnedOrder != item.file.pinnedOrder
                || current.file.filenameOriginal != item.file.filenameOriginal
                || current.file.updatedAt != item.file.updatedAt
                || current.file.deletedAt != item.file.deletedAt {
                return true
            }
        }
        return false
    }

    func upsertRemoteItem(_ item: IngestionListItem) {
        if let index = remoteItems.firstIndex(where: { $0.file.id == item.file.id }) {
            remoteItems[index] = item
        } else {
            remoteItems.append(item)
        }
        items = mergeItems(remoteItems)
        persistListCache()
        updateWidgetData()
    }

    func mergeItems(_ remote: [IngestionListItem]) -> [IngestionListItem] {
        let remoteIds = Set(remote.map { $0.file.id })
        let filteredLocal = localItems.filter { !remoteIds.contains($0.key) }
        if filteredLocal.count != localItems.count {
            localItems = filteredLocal
            localUploadRecords = localUploadRecords.filter { !remoteIds.contains($0.key) }
            persistLocalUploads()
        }
        var merged = remote
        let sortedLocal = localItems.values.sorted { lhs, rhs in
            let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
            return leftDate > rightDate
        }
        merged.append(contentsOf: sortedLocal)
        return merged
    }

    func updatingPinned(_ file: IngestedFileMeta, pinned: Bool) -> IngestedFileMeta {
        IngestedFileMeta(
            id: file.id,
            filenameOriginal: file.filenameOriginal,
            path: file.path,
            mimeOriginal: file.mimeOriginal,
            sizeBytes: file.sizeBytes,
            sha256: file.sha256,
            pinned: pinned,
            pinnedOrder: file.pinnedOrder,
            category: file.category,
            sourceUrl: file.sourceUrl,
            sourceMetadata: file.sourceMetadata,
            createdAt: file.createdAt,
            updatedAt: file.updatedAt,
            deletedAt: file.deletedAt
        )
    }

    func updatingFilename(_ file: IngestedFileMeta, filename: String) -> IngestedFileMeta {
        IngestedFileMeta(
            id: file.id,
            filenameOriginal: filename,
            path: file.path,
            mimeOriginal: file.mimeOriginal,
            sizeBytes: file.sizeBytes,
            sha256: file.sha256,
            pinned: file.pinned,
            pinnedOrder: file.pinnedOrder,
            category: file.category,
            sourceUrl: file.sourceUrl,
            sourceMetadata: file.sourceMetadata,
            createdAt: file.createdAt,
            updatedAt: file.updatedAt,
            deletedAt: file.deletedAt
        )
    }

    func applyMetaUpdate(_ incoming: IngestionMetaResponse, persist: Bool) {
        guard shouldUpdateMeta(incoming) else {
            return
        }
        activeMeta = incoming
        updateFilenameForItems(fileId: incoming.file.id, filename: incoming.file.filenameOriginal)
        if persist {
            cache.set(
                key: CacheKeys.ingestionMeta(fileId: incoming.file.id),
                value: incoming,
                ttlSeconds: CachePolicy.ingestionMeta
            )
            let lastSyncAt = Date()
            offlineStore?.set(
                key: CacheKeys.ingestionMeta(fileId: incoming.file.id),
                entityType: "file",
                value: incoming,
                lastSyncAt: lastSyncAt
            )
        }
    }

    func shouldUpdateMeta(_ incoming: IngestionMetaResponse) -> Bool {
        guard let current = activeMeta else {
            return true
        }
        return current.file.pinned != incoming.file.pinned
            || current.file.pinnedOrder != incoming.file.pinnedOrder
            || current.job.updatedAt != incoming.job.updatedAt
            || current.job.status != incoming.job.status
            || current.job.stage != incoming.job.stage
            || current.derivatives.count != incoming.derivatives.count
    }

    func persistListCache() {
        cache.set(
            key: CacheKeys.ingestionList,
            value: IngestionListResponse(items: remoteItems),
            ttlSeconds: CachePolicy.ingestionList
        )
        let lastSyncAt = Date()
        offlineStore?.set(
            key: CacheKeys.ingestionList,
            entityType: "ingestionList",
            value: IngestionListResponse(items: remoteItems),
            lastSyncAt: lastSyncAt
        )
    }

    func updateFilenameForItems(fileId: String, filename: String) {
        var didUpdate = false
        if let index = remoteItems.firstIndex(where: { $0.file.id == fileId }) {
            let existing = remoteItems[index]
            if existing.file.filenameOriginal != filename {
                let updatedFile = updatingFilename(existing.file, filename: filename)
                remoteItems[index] = IngestionListItem(
                    file: updatedFile,
                    job: existing.job,
                    recommendedViewer: existing.recommendedViewer
                )
                didUpdate = true
            }
        }
        if let local = localItems[fileId], local.file.filenameOriginal != filename {
            let updatedFile = updatingFilename(local.file, filename: filename)
            let updated = IngestionListItem(
                file: updatedFile,
                job: local.job,
                recommendedViewer: local.recommendedViewer
            )
            setLocalUpload(item: updated, bookmarkData: nil)
            didUpdate = true
        }
        if didUpdate {
            items = mergeItems(remoteItems)
            persistListCache()
        }
    }

    func loadLocalUploads() {
        guard let data = userDefaults.data(forKey: localUploadsKey) else { return }
        guard let records = try? JSONDecoder().decode([String: LocalUploadRecord].self, from: data) else { return }
        localUploadRecords = records
        localItems = records.mapValues { $0.item }
        items = mergeItems(remoteItems)
    }

    func persistLocalUploads() {
        guard let data = try? JSONEncoder().encode(localUploadRecords) else { return }
        userDefaults.set(data, forKey: localUploadsKey)
    }

    func setLocalUpload(item: IngestionListItem, bookmarkData: Data?) {
        localItems[item.file.id] = item
        let existingBookmark = bookmarkData ?? localUploadRecords[item.file.id]?.bookmarkData
        localUploadRecords[item.file.id] = LocalUploadRecord(item: item, bookmarkData: existingBookmark)
        persistLocalUploads()
    }

    func removeLocalUploadRecord(fileId: String) {
        localItems.removeValue(forKey: fileId)
        localUploadRecords.removeValue(forKey: fileId)
        persistLocalUploads()
    }
}

struct LocalUploadRecord: Codable {
    let item: IngestionListItem
    let bookmarkData: Data?
}

struct LocalUploadResumeItem {
    let item: IngestionListItem
    let bookmarkData: Data
}
