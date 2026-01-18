import Foundation
import Combine

@MainActor
public final class IngestionStore: ObservableObject {
    @Published public private(set) var items: [IngestionListItem] = []
    @Published public private(set) var activeMeta: IngestionMetaResponse? = nil
    @Published public private(set) var isOffline: Bool = false

    private let api: any IngestionProviding
    private let cache: CacheClient
    private var isRefreshingList = false
    private var refreshingMetaIds = Set<String>()

    public init(api: any IngestionProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func loadList(force: Bool = false) async throws {
        let cached: IngestionListResponse? = force ? nil : cache.get(key: CacheKeys.ingestionList)
        if let cached {
            applyListUpdate(cached.items, persist: false)
            Task { [weak self] in
                await self?.refreshList()
            }
            return
        }
        let response = try await api.list()
        isOffline = false
        applyListUpdate(response.items, persist: true)
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
        activeMeta = nil
    }

    public func applyIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>) {
        let fileId = payload.record?.id ?? payload.oldRecord?.id
        switch payload.eventType {
        case .delete:
            if let fileId {
                items.removeAll { $0.file.id == fileId }
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
            let job = items.first(where: { $0.file.id == mapped.id })?.job ?? IngestionJob(
                status: nil,
                stage: nil,
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 0,
                updatedAt: nil
            )
            upsertItem(IngestionListItem(file: mapped, job: job, recommendedViewer: nil))
        }
    }

    public func applyFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) {
        guard let record = payload.record else {
            return
        }
        guard let index = items.firstIndex(where: { $0.file.id == record.fileId }) else {
            return
        }
        let job = RealtimeMappers.mapFileJob(record)
        let existing = items[index]
        items[index] = IngestionListItem(file: existing.file, job: job, recommendedViewer: existing.recommendedViewer)
        persistListCache()
    }

    public func updatePinned(fileId: String, pinned: Bool) {
        if let index = items.firstIndex(where: { $0.file.id == fileId }) {
            let existing = items[index]
            let updatedFile = updatingPinned(existing.file, pinned: pinned)
            items[index] = IngestionListItem(file: updatedFile, job: existing.job, recommendedViewer: existing.recommendedViewer)
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
        persistListCache()
    }

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
        items = incoming
        if persist {
            persistListCache()
        }
    }

    private func shouldUpdateList(_ incoming: [IngestionListItem]) -> Bool {
        guard items.count == incoming.count else {
            return true
        }
        let existing = Dictionary(uniqueKeysWithValues: items.map { ($0.file.id, $0) })
        for item in incoming {
            guard let current = existing[item.file.id] else {
                return true
            }
            if current.job.updatedAt != item.job.updatedAt
                || current.job.status != item.job.status
                || current.job.stage != item.job.stage
                || current.file.pinned != item.file.pinned
                || current.file.pinnedOrder != item.file.pinnedOrder {
                return true
            }
        }
        return false
    }

    private func upsertItem(_ item: IngestionListItem) {
        if let index = items.firstIndex(where: { $0.file.id == item.file.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        persistListCache()
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

    private func applyMetaUpdate(_ incoming: IngestionMetaResponse, persist: Bool) {
        guard shouldUpdateMeta(incoming) else {
            return
        }
        activeMeta = incoming
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
            value: IngestionListResponse(items: items),
            ttlSeconds: CachePolicy.ingestionList
        )
    }
}
