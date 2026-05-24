import Foundation
import sideBarShared

// MARK: - Helpers

extension IngestionStore {
    func refreshList() async {
        guard canAttemptBackgroundRefresh() else {
            return
        }
        guard canAttemptServerRead else {
            return
        }
        guard !isRefreshingList else {
            return
        }
        isRefreshingList = true
        defer { isRefreshingList = false }
        do {
            let response = try await api.list()
            isOffline = false
            applyListUpdate(response.items, persist: true)
            markBackgroundRefreshSuccess()
        } catch {
            markBackgroundRefreshFailure()
            if Self.isNetworkError(error) {
                isOffline = true
            }
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    func refreshMeta(fileId: String) async {
        guard canAttemptBackgroundRefresh() else {
            return
        }
        guard canAttemptServerRead else {
            return
        }
        guard !refreshingMetaIds.contains(fileId) else {
            return
        }
        refreshingMetaIds.insert(fileId)
        defer { refreshingMetaIds.remove(fileId) }
        do {
            let response = try await api.getMeta(fileId: fileId)
            isOffline = false
            applyMetaUpdate(response, persist: true)
            markBackgroundRefreshSuccess()
        } catch {
            markBackgroundRefreshFailure()
            if Self.isNetworkError(error) {
                isOffline = true
            }
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    static func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .dataNotAllowed,
                 .internationalRoamingOff:
                return true
            default:
                return false
            }
        }
        return false
    }

    func applyListUpdate(_ incoming: [IngestionListItem], persist: Bool) {
        let filteredIncoming = incoming.filter(shouldIncludeIngestionItem)
        syncActiveMeta(with: filteredIncoming, persist: persist)
        guard shouldUpdateList(filteredIncoming) else {
            updateWidgetData()
            return
        }
        remoteItems = filteredIncoming
        items = mergeItems(filteredIncoming)
        if persist {
            persistListCache()
            indexFilesInSpotlight(filteredIncoming)
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
        widgetDataManager.store(data, for: .files)
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

    func fallbackRecommendedViewer(for file: IngestedFileMeta) -> String? {
        let normalizedMime = normalizedMimeType(file.mimeOriginal)
        if normalizedMime == "application/pdf" {
            return "viewer_pdf"
        }
        if normalizedMime.hasPrefix("video/"), file.sourceUrl?.isEmpty == false {
            return "viewer_video"
        }
        if normalizedMime.hasPrefix("image/") {
            return "image_original"
        }
        if normalizedMime.hasPrefix("audio/") {
            return "audio_original"
        }
        if normalizedMime.hasPrefix("text/")
            || normalizedMime == "application/json"
            || normalizedMime.contains("json") {
            return "text_original"
        }
        return nil
    }

    private func normalizedMimeType(_ mimeType: String) -> String {
        mimeType
            .split(separator: ";")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? mimeType.lowercased()
    }

    func applyMetaUpdate(_ incoming: IngestionMetaResponse, persist: Bool) {
        guard shouldUpdateMeta(incoming) else {
            return
        }
        activeMeta = incoming
        updateFilenameForItems(fileId: incoming.file.id, filename: incoming.file.filenameOriginal)
        if persist {
            persistMeta(incoming)
        }
    }

    func shouldUpdateMeta(_ incoming: IngestionMetaResponse) -> Bool {
        guard let current = activeMeta else {
            return true
        }
        return current.file.id != incoming.file.id
            || current.file.filenameOriginal != incoming.file.filenameOriginal
            || current.file.updatedAt != incoming.file.updatedAt
            || current.file.path != incoming.file.path
            || current.file.mimeOriginal != incoming.file.mimeOriginal
            || current.file.sizeBytes != incoming.file.sizeBytes
            || current.file.pinned != incoming.file.pinned
            || current.file.pinnedOrder != incoming.file.pinnedOrder
            || current.job.updatedAt != incoming.job.updatedAt
            || current.job.status != incoming.job.status
            || current.job.stage != incoming.job.stage
            || current.recommendedViewer != incoming.recommendedViewer
            || !current.derivatives.elementsEqual(incoming.derivatives, by: { lhs, rhs in
                lhs.id == rhs.id
                    && lhs.kind == rhs.kind
                    && lhs.storageKey == rhs.storageKey
                    && lhs.mime == rhs.mime
                    && lhs.sizeBytes == rhs.sizeBytes
            })
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

    func syncActiveMeta(with items: [IngestionListItem], persist: Bool) {
        guard let activeMeta,
              let item = items.first(where: { $0.file.id == activeMeta.file.id }) else {
            return
        }
        let updated = updateMeta(activeMeta, with: item)
        guard shouldSyncMetaMetadata(current: activeMeta, updated: updated) else {
            return
        }
        self.activeMeta = updated
        guard persist else {
            return
        }
        persistMeta(updated)
    }

    func updateMeta(_ meta: IngestionMetaResponse, with item: IngestionListItem) -> IngestionMetaResponse {
        IngestionMetaResponse(
            file: item.file,
            job: item.job,
            derivatives: meta.derivatives,
            recommendedViewer: item.recommendedViewer ?? meta.recommendedViewer
        )
    }

    func shouldSyncMetaMetadata(current: IngestionMetaResponse, updated: IngestionMetaResponse) -> Bool {
        current.file.filenameOriginal != updated.file.filenameOriginal
            || current.file.path != updated.file.path
            || current.file.mimeOriginal != updated.file.mimeOriginal
            || current.file.sizeBytes != updated.file.sizeBytes
            || current.file.pinned != updated.file.pinned
            || current.file.pinnedOrder != updated.file.pinnedOrder
            || current.file.category != updated.file.category
            || current.file.sourceUrl != updated.file.sourceUrl
            || sourceMetadataChanged(current.file.sourceMetadata, updated.file.sourceMetadata)
            || current.file.updatedAt != updated.file.updatedAt
            || current.file.deletedAt != updated.file.deletedAt
            || current.job.status != updated.job.status
            || current.job.stage != updated.job.stage
            || current.job.errorCode != updated.job.errorCode
            || current.job.errorMessage != updated.job.errorMessage
            || current.job.userMessage != updated.job.userMessage
            || current.job.progress != updated.job.progress
            || current.job.attempts != updated.job.attempts
            || current.job.updatedAt != updated.job.updatedAt
            || current.recommendedViewer != updated.recommendedViewer
    }

    func sourceMetadataChanged(
        _ current: [String: AnyCodable]?,
        _ updated: [String: AnyCodable]?
    ) -> Bool {
        switch (current, updated) {
        case (nil, nil):
            return false
        case (nil, _), (_, nil):
            return true
        case let (.some(current), .some(updated)):
            let encoder = JSONEncoder()
            guard let currentData = try? encoder.encode(current),
                  let updatedData = try? encoder.encode(updated) else {
                return true
            }
            return currentData != updatedData
        }
    }

    func persistMeta(_ meta: IngestionMetaResponse) {
        cache.set(
            key: CacheKeys.ingestionMeta(fileId: meta.file.id),
            value: meta,
            ttlSeconds: CachePolicy.ingestionMeta
        )
        let lastSyncAt = Date()
        offlineStore?.set(
            key: CacheKeys.ingestionMeta(fileId: meta.file.id),
            entityType: "file",
            value: meta,
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
        let sanitizedRecords = records.filter { fileId, record in
            isValidPersistedLocalUploadID(fileId) && isValidPersistedLocalUploadID(record.item.file.id)
        }
        localUploadRecords = sanitizedRecords
        localItems = sanitizedRecords.mapValues { $0.item }
        if sanitizedRecords.count != records.count {
            persistLocalUploads()
        }
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

    func removeLocalUploadBookmark(fileId: String) {
        guard let record = localUploadRecords[fileId] else { return }
        localUploadRecords[fileId] = LocalUploadRecord(item: record.item, bookmarkData: nil)
        persistLocalUploads()
    }

    func removeLocalUploadRecord(fileId: String) {
        localItems.removeValue(forKey: fileId)
        localUploadRecords.removeValue(forKey: fileId)
        persistLocalUploads()
    }

    func isValidPersistedLocalUploadID(_ fileId: String) -> Bool {
        IdentifierValidation.isLocalPlaceholderID(fileId) || IdentifierValidation.isServerFileID(fileId)
    }

    func shouldIncludeIngestionItem(_ item: IngestionListItem) -> Bool {
        if item.file.deletedAt != nil {
            return false
        }
        if (item.file.path ?? "").lowercased().hasSuffix("/ai/ai.md") {
            return false
        }
        if metadataBool(item.file.sourceMetadata, key: "website_transcript") == true {
            return false
        }
        return true
    }

    func metadataBool(_ metadata: [String: AnyCodable]?, key: String) -> Bool? {
        guard let value = metadata?[key]?.value else { return nil }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }
        return nil
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
