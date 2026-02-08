import Foundation
import sideBarShared

extension WebsitesStore {
    func applyTranscriptQueuedUpdate(
        websiteId: String,
        videoId: String,
        status: String,
        fileId: String?
    ) {
        guard let active, active.id == websiteId else { return }
        var transcripts = active.youtubeTranscripts ?? [:]
        let timestamp = ISO8601DateFormatter().string(from: Date())
        transcripts[videoId] = WebsiteTranscriptEntry(
            status: status,
            fileId: fileId,
            updatedAt: timestamp,
            error: nil
        )

        let updatedDetail = WebsiteDetail(
            id: active.id,
            title: active.title,
            url: active.url,
            urlFull: active.urlFull,
            domain: active.domain,
            content: active.content,
            source: active.source,
            savedAt: active.savedAt,
            publishedAt: active.publishedAt,
            pinned: active.pinned,
            pinnedOrder: active.pinnedOrder,
            archived: active.archived,
            faviconUrl: active.faviconUrl,
            faviconR2Key: active.faviconR2Key,
            youtubeTranscripts: transcripts,
            readingTime: active.readingTime,
            updatedAt: active.updatedAt,
            lastOpenedAt: active.lastOpenedAt
        )
        applyDetailUpdate(updatedDetail, persist: true)
    }

    func applyTranscriptReadyDetail(_ detail: WebsiteDetail) {
        applyDetailUpdate(detail, persist: true)
    }

    func currentUpdatedAt(id: String) -> String? {
        websiteItem(for: id)?.updatedAt
    }

    func enqueueRename(id: String, title: String) async throws {
        let operationId = UUID().uuidString
        let payload = WebsiteOperationPayload(
            operationId: operationId,
            op: "rename",
            id: id,
            title: title,
            clientUpdatedAt: websiteItem(for: id)?.updatedAt
        )
        let snapshot = makeServerSnapshot(websiteId: id)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .rename,
            entityType: .website,
            entityId: id,
            payload: payload,
            serverSnapshot: snapshot
        )
        applyLocalUpdate(id: id) { item in
            WebsiteItem(
                id: item.id,
                title: title,
                url: item.url,
                domain: item.domain,
                savedAt: item.savedAt,
                publishedAt: item.publishedAt,
                pinned: item.pinned,
                pinnedOrder: item.pinnedOrder,
                archived: item.archived,
                faviconUrl: item.faviconUrl,
                faviconR2Key: item.faviconR2Key,
                youtubeTranscripts: item.youtubeTranscripts,
                readingTime: item.readingTime,
                updatedAt: item.updatedAt,
                lastOpenedAt: item.lastOpenedAt,
                deletedAt: item.deletedAt
            )
        }
    }

    func enqueuePin(id: String, pinned: Bool) async throws {
        let operationId = UUID().uuidString
        let payload = WebsiteOperationPayload(
            operationId: operationId,
            op: "pin",
            id: id,
            pinned: pinned,
            clientUpdatedAt: websiteItem(for: id)?.updatedAt
        )
        let snapshot = makeServerSnapshot(websiteId: id)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .pin,
            entityType: .website,
            entityId: id,
            payload: payload,
            serverSnapshot: snapshot
        )
        applyLocalUpdate(id: id) { item in
            WebsiteItem(
                id: item.id,
                title: item.title,
                url: item.url,
                domain: item.domain,
                savedAt: item.savedAt,
                publishedAt: item.publishedAt,
                pinned: pinned,
                pinnedOrder: item.pinnedOrder,
                archived: item.archived,
                faviconUrl: item.faviconUrl,
                faviconR2Key: item.faviconR2Key,
                youtubeTranscripts: item.youtubeTranscripts,
                readingTime: item.readingTime,
                updatedAt: item.updatedAt,
                lastOpenedAt: item.lastOpenedAt,
                deletedAt: item.deletedAt
            )
        }
    }

    func enqueueArchive(id: String, archived: Bool) async throws {
        let operationId = UUID().uuidString
        let payload = WebsiteOperationPayload(
            operationId: operationId,
            op: "archive",
            id: id,
            archived: archived,
            clientUpdatedAt: websiteItem(for: id)?.updatedAt
        )
        let snapshot = makeServerSnapshot(websiteId: id)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .archive,
            entityType: .website,
            entityId: id,
            payload: payload,
            serverSnapshot: snapshot
        )
        applyLocalUpdate(id: id) { item in
            WebsiteItem(
                id: item.id,
                title: item.title,
                url: item.url,
                domain: item.domain,
                savedAt: item.savedAt,
                publishedAt: item.publishedAt,
                pinned: item.pinned,
                pinnedOrder: item.pinnedOrder,
                archived: archived,
                faviconUrl: item.faviconUrl,
                faviconR2Key: item.faviconR2Key,
                youtubeTranscripts: item.youtubeTranscripts,
                readingTime: item.readingTime,
                updatedAt: item.updatedAt,
                lastOpenedAt: item.lastOpenedAt,
                deletedAt: item.deletedAt
            )
        }
        if archived, active?.id == id {
            active = nil
        }
    }

    func enqueueDelete(id: String) async throws {
        let operationId = UUID().uuidString
        let payload = WebsiteOperationPayload(
            operationId: operationId,
            op: "delete",
            id: id,
            clientUpdatedAt: websiteItem(for: id)?.updatedAt
        )
        let snapshot = makeServerSnapshot(websiteId: id)
        try await enqueueOfflineOperation(
            writeQueue: writeQueue,
            operation: .delete,
            entityType: .website,
            entityId: id,
            payload: payload,
            serverSnapshot: snapshot
        )
        removeItem(id: id, persist: true)
    }

    func applySyncItem(_ item: WebsiteItem) {
        if item.deletedAt != nil {
            removeItem(id: item.id, persist: true)
            return
        }
        updateListItem(item, persist: true)
    }

    private func applyLocalUpdate(id: String, update: (WebsiteItem) -> WebsiteItem) {
        guard let current = websiteItem(for: id) else { return }
        let updated = update(current)
        updateListItem(updated, persist: true)
    }

    private func websiteItem(for id: String) -> WebsiteItem? {
        let listItem = items.first(where: { $0.id == id })
        let activeItem = activeItem(for: id)
        guard listItem != nil || activeItem != nil else {
            return nil
        }
        if let listItem, let activeItem {
            return newerItem(between: listItem, and: activeItem)
        }
        return listItem ?? activeItem
    }

    private func activeItem(for id: String) -> WebsiteItem? {
        guard let active, active.id == id else { return nil }
        return WebsiteItem(
            id: active.id,
            title: active.title,
            url: active.url,
            domain: active.domain,
            savedAt: active.savedAt,
            publishedAt: active.publishedAt,
            pinned: active.pinned,
            pinnedOrder: active.pinnedOrder,
            archived: active.archived,
            faviconUrl: active.faviconUrl,
            faviconR2Key: active.faviconR2Key,
            youtubeTranscripts: active.youtubeTranscripts,
            readingTime: active.readingTime,
            updatedAt: active.updatedAt,
            lastOpenedAt: active.lastOpenedAt,
            deletedAt: nil
        )
    }

    private func newerItem(between lhs: WebsiteItem, and rhs: WebsiteItem) -> WebsiteItem {
        let lhsUpdated = DateParsing.parseISO8601(lhs.updatedAt)
        let rhsUpdated = DateParsing.parseISO8601(rhs.updatedAt)
        switch (lhsUpdated, rhsUpdated) {
        case let (leftDate?, rightDate?):
            return leftDate >= rightDate ? lhs : rhs
        case (_?, nil):
            return lhs
        case (nil, _?):
            return rhs
        case (nil, nil):
            if lhs.updatedAt == nil, rhs.updatedAt != nil {
                return rhs
            }
            return lhs
        }
    }

    private func makeServerSnapshot(websiteId: String) -> ServerSnapshot? {
        guard let item = websiteItem(for: websiteId) else { return nil }
        let snapshot = WebsiteSnapshot(
            updatedAt: item.updatedAt,
            title: item.title,
            pinned: item.pinned,
            pinnedOrder: item.pinnedOrder,
            archived: item.archived
        )
        return ServerSnapshot(
            entityType: .website,
            entityId: websiteId,
            capturedAt: Date(),
            payload: .website(snapshot)
        )
    }
}
