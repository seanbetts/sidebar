import Foundation
import Combine

// MARK: - IngestionStore

public final class IngestionStore: CachedStoreBase<IngestionListResponse> {
    @Published public private(set) var items: [IngestionListItem] = []
    @Published public private(set) var activeMeta: IngestionMetaResponse? = nil
    @Published public private(set) var isOffline: Bool = false

    private let api: any IngestionProviding
    private var remoteItems: [IngestionListItem] = []
    private var localItems: [String: IngestionListItem] = [:]
    private var isRefreshingList = false
    private var refreshingMetaIds = Set<String>()

    public init(api: any IngestionProviding, cache: CacheClient) {
        self.api = api
        super.init(cache: cache)
    }

    // MARK: - CachedStoreBase Overrides

    public override var cacheKey: String { CacheKeys.ingestionList }
    public override var cacheTTL: TimeInterval { CachePolicy.ingestionList }

    public override func fetchFromAPI() async throws -> IngestionListResponse {
        let response = try await api.list()
        isOffline = false
        return response
    }

    public override func applyData(_ data: IngestionListResponse, persist: Bool) {
        applyListUpdate(data.items, persist: persist)
    }

    public override func backgroundRefresh() async {
        await refreshList()
    }

    // MARK: - Public API

    public func loadList(force: Bool = false) async throws {
        try await loadWithCache(force: force)
    }

    public func loadMeta(fileId: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.ingestionMeta(fileId: fileId)
        if !force, let cached: IngestionMetaResponse = cache.get(key: cacheKey) {
            applyMetaUpdate(cached, persist: false)
            Task { [weak self] in
                await self?.refreshMeta(fileId: fileId)
            }
            return
        }
        let response = try await api.getMeta(fileId: fileId)
        isOffline = false
        applyMetaUpdate(response, persist: true)
    }

    public func invalidateList() {
        cache.remove(key: CacheKeys.ingestionList)
    }

    public func clearActiveMeta() {
        activeMeta = nil
    }

    public func reset() {
        items = []
        remoteItems = []
        localItems = [:]
        activeMeta = nil
    }

    public func applyIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>) {
        let fileId = payload.record?.id ?? payload.oldRecord?.id
        switch payload.eventType {
        case .delete:
            if let fileId {
                remoteItems.removeAll { $0.file.id == fileId }
                items = mergeItems(remoteItems)
                persistListCache()
                if activeMeta?.file.id == fileId {
                    activeMeta = nil
                }
            }
        case .insert, .update:
            guard let record = payload.record,
                  let mapped = RealtimeMappers.mapIngestedFile(record) else {
                return
            }
            let job = remoteItems.first(where: { $0.file.id == mapped.id })?.job ?? IngestionJob(
                status: nil,
                stage: nil,
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 0,
                updatedAt: nil
            )
            upsertRemoteItem(IngestionListItem(file: mapped, job: job, recommendedViewer: nil))
        }
    }

    public func applyFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) {
        guard let record = payload.record else {
            return
        }
        let job = RealtimeMappers.mapFileJob(record)
        if let index = remoteItems.firstIndex(where: { $0.file.id == record.fileId }) {
            let existing = remoteItems[index]
            remoteItems[index] = IngestionListItem(file: existing.file, job: job, recommendedViewer: existing.recommendedViewer)
        } else if let local = localItems[record.fileId] {
            localItems[record.fileId] = IngestionListItem(file: local.file, job: job, recommendedViewer: local.recommendedViewer)
        } else {
            return
        }
        items = mergeItems(remoteItems)
        persistListCache()
    }

    public func updatePinned(fileId: String, pinned: Bool) {
        if let index = remoteItems.firstIndex(where: { $0.file.id == fileId }) {
            let existing = remoteItems[index]
            let updatedFile = updatingPinned(existing.file, pinned: pinned)
            remoteItems[index] = IngestionListItem(
                file: updatedFile,
                job: existing.job,
                recommendedViewer: existing.recommendedViewer
            )
        }
        if let local = localItems[fileId] {
            let updatedFile = updatingPinned(local.file, pinned: pinned)
            localItems[fileId] = IngestionListItem(
                file: updatedFile,
                job: local.job,
                recommendedViewer: local.recommendedViewer
            )
        }
        if let meta = activeMeta, meta.file.id == fileId {
            let updatedFile = updatingPinned(meta.file, pinned: pinned)
            let updatedMeta = IngestionMetaResponse(
                file: updatedFile,
                job: meta.job,
                derivatives: meta.derivatives,
                recommendedViewer: meta.recommendedViewer
            )
            activeMeta = updatedMeta
            cache.set(
                key: CacheKeys.ingestionMeta(fileId: updatedMeta.file.id),
                value: updatedMeta,
                ttlSeconds: CachePolicy.ingestionMeta
            )
        }
        items = mergeItems(remoteItems)
        persistListCache()
    }

    public func updateFilename(fileId: String, filename: String) {
        if let index = remoteItems.firstIndex(where: { $0.file.id == fileId }) {
            let existing = remoteItems[index]
            let updatedFile = updatingFilename(existing.file, filename: filename)
            remoteItems[index] = IngestionListItem(
                file: updatedFile,
                job: existing.job,
                recommendedViewer: existing.recommendedViewer
            )
        }
        if let local = localItems[fileId] {
            let updatedFile = updatingFilename(local.file, filename: filename)
            localItems[fileId] = IngestionListItem(
                file: updatedFile,
                job: local.job,
                recommendedViewer: local.recommendedViewer
            )
        }
        if let meta = activeMeta, meta.file.id == fileId {
            let updatedFile = updatingFilename(meta.file, filename: filename)
            let updatedMeta = IngestionMetaResponse(
                file: updatedFile,
                job: meta.job,
                derivatives: meta.derivatives,
                recommendedViewer: meta.recommendedViewer
            )
            activeMeta = updatedMeta
            cache.set(
                key: CacheKeys.ingestionMeta(fileId: updatedMeta.file.id),
                value: updatedMeta,
                ttlSeconds: CachePolicy.ingestionMeta
            )
        }
        items = mergeItems(remoteItems)
        persistListCache()
    }

    public func updateJob(fileId: String, job: IngestionJob, recommendedViewer: String?) {
        if let index = remoteItems.firstIndex(where: { $0.file.id == fileId }) {
            let existing = remoteItems[index]
            remoteItems[index] = IngestionListItem(
                file: existing.file,
                job: job,
                recommendedViewer: recommendedViewer ?? existing.recommendedViewer
            )
        }
        if let local = localItems[fileId] {
            localItems[fileId] = IngestionListItem(
                file: local.file,
                job: job,
                recommendedViewer: recommendedViewer ?? local.recommendedViewer
            )
        }
        if let meta = activeMeta, meta.file.id == fileId {
            let updatedMeta = IngestionMetaResponse(
                file: meta.file,
                job: job,
                derivatives: meta.derivatives,
                recommendedViewer: recommendedViewer ?? meta.recommendedViewer
            )
            activeMeta = updatedMeta
            cache.set(
                key: CacheKeys.ingestionMeta(fileId: updatedMeta.file.id),
                value: updatedMeta,
                ttlSeconds: CachePolicy.ingestionMeta
            )
        }
        items = mergeItems(remoteItems)
        persistListCache()
    }

    public func removeItem(fileId: String) {
        remoteItems.removeAll { $0.file.id == fileId }
        localItems.removeValue(forKey: fileId)
        items = mergeItems(remoteItems)
        if activeMeta?.file.id == fileId {
            activeMeta = nil
        }
        persistListCache()
        cache.remove(key: CacheKeys.ingestionMeta(fileId: fileId))
    }

    public func addLocalUpload(_ item: IngestionListItem) {
        localItems[item.file.id] = item
        items = mergeItems(remoteItems)
    }

    public func updateLocalUpload(
        fileId: String,
        status: String? = nil,
        stage: String? = nil,
        progress: Double? = nil,
        errorMessage: String? = nil
    ) {
        guard let existing = localItems[fileId] else { return }
        let updatedJob = IngestionJob(
            status: status ?? existing.job.status,
            stage: stage ?? existing.job.stage,
            errorCode: existing.job.errorCode,
            errorMessage: errorMessage ?? existing.job.errorMessage,
            userMessage: existing.job.userMessage,
            progress: progress ?? existing.job.progress,
            attempts: existing.job.attempts,
            updatedAt: existing.job.updatedAt
        )
        localItems[fileId] = IngestionListItem(
            file: existing.file,
            job: updatedJob,
            recommendedViewer: existing.recommendedViewer
        )
        items = mergeItems(remoteItems)
    }

    public func replaceLocalUpload(
        tempId: String,
        fileId: String,
        filename: String,
        mimeType: String,
        sizeBytes: Int,
        sourceUrl: String? = nil
    ) {
        guard let existing = localItems[tempId] else { return }
        localItems.removeValue(forKey: tempId)
        let updatedFile = IngestedFileMeta(
            id: fileId,
            filenameOriginal: filename,
            path: existing.file.path,
            mimeOriginal: mimeType,
            sizeBytes: sizeBytes,
            sha256: existing.file.sha256,
            pinned: existing.file.pinned,
            pinnedOrder: existing.file.pinnedOrder,
            category: existing.file.category,
            sourceUrl: sourceUrl ?? existing.file.sourceUrl,
            sourceMetadata: existing.file.sourceMetadata,
            createdAt: existing.file.createdAt
        )
        let updatedJob = IngestionJob(
            status: existing.job.status,
            stage: existing.job.stage,
            errorCode: existing.job.errorCode,
            errorMessage: existing.job.errorMessage,
            userMessage: existing.job.userMessage,
            progress: existing.job.progress,
            attempts: existing.job.attempts,
            updatedAt: existing.job.updatedAt
        )
        localItems[fileId] = IngestionListItem(
            file: updatedFile,
            job: updatedJob,
            recommendedViewer: existing.recommendedViewer
        )
        items = mergeItems(remoteItems)
    }

    public func removeLocalUpload(fileId: String) {
        localItems.removeValue(forKey: fileId)
        items = mergeItems(remoteItems)
    }

    // MARK: - Private

    private func refreshList() async {
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

    private func refreshMeta(fileId: String) async {
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

    private func applyListUpdate(_ incoming: [IngestionListItem], persist: Bool) {
        guard shouldUpdateList(incoming) else {
            return
        }
        remoteItems = incoming
        items = mergeItems(incoming)
        if persist {
            persistListCache()
        }
    }

    private func shouldUpdateList(_ incoming: [IngestionListItem]) -> Bool {
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
                || current.file.filenameOriginal != item.file.filenameOriginal {
                return true
            }
        }
        return false
    }

    private func upsertRemoteItem(_ item: IngestionListItem) {
        if let index = remoteItems.firstIndex(where: { $0.file.id == item.file.id }) {
            remoteItems[index] = item
        } else {
            remoteItems.append(item)
        }
        items = mergeItems(remoteItems)
        persistListCache()
    }

    private func mergeItems(_ remote: [IngestionListItem]) -> [IngestionListItem] {
        let remoteIds = Set(remote.map { $0.file.id })
        localItems = localItems.filter { !remoteIds.contains($0.key) }
        var merged = remote
        let sortedLocal = localItems.values.sorted { lhs, rhs in
            let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
            return leftDate > rightDate
        }
        merged.append(contentsOf: sortedLocal)
        return merged
    }

    private func updatingPinned(_ file: IngestedFileMeta, pinned: Bool) -> IngestedFileMeta {
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
            createdAt: file.createdAt
        )
    }

    private func updatingFilename(_ file: IngestedFileMeta, filename: String) -> IngestedFileMeta {
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
            createdAt: file.createdAt
        )
    }

    private func applyMetaUpdate(_ incoming: IngestionMetaResponse, persist: Bool) {
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
        }
    }

    private func shouldUpdateMeta(_ incoming: IngestionMetaResponse) -> Bool {
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

    private func persistListCache() {
        cache.set(
            key: CacheKeys.ingestionList,
            value: IngestionListResponse(items: remoteItems),
            ttlSeconds: CachePolicy.ingestionList
        )
    }

    private func updateFilenameForItems(fileId: String, filename: String) {
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
            localItems[fileId] = IngestionListItem(
                file: updatedFile,
                job: local.job,
                recommendedViewer: local.recommendedViewer
            )
            didUpdate = true
        }
        if didUpdate {
            items = mergeItems(remoteItems)
            persistListCache()
        }
    }
}
