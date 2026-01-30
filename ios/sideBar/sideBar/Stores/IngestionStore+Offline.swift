import Foundation

// MARK: - Offline Queueing

extension IngestionStore {
    func currentUpdatedAt(fileId: String) -> String? {
        fileMeta(for: fileId)?.updatedAt
    }

    func enqueuePin(fileId: String, pinned: Bool) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let operationId = UUID().uuidString
        let payload = IngestionOperationPayload(
            operationId: operationId,
            op: "pin",
            id: fileId,
            pinned: pinned,
            clientUpdatedAt: fileMeta(for: fileId)?.updatedAt
        )
        let snapshot = makeServerSnapshot(fileId: fileId)
        try await writeQueue.enqueue(
            operation: .pin,
            entityType: .file,
            entityId: fileId,
            payload: payload,
            serverSnapshot: snapshot
        )
        updatePinned(fileId: fileId, pinned: pinned)
    }

    func enqueueRename(fileId: String, filename: String) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let operationId = UUID().uuidString
        let payload = IngestionOperationPayload(
            operationId: operationId,
            op: "rename",
            id: fileId,
            filename: filename,
            clientUpdatedAt: fileMeta(for: fileId)?.updatedAt
        )
        let snapshot = makeServerSnapshot(fileId: fileId)
        try await writeQueue.enqueue(
            operation: .rename,
            entityType: .file,
            entityId: fileId,
            payload: payload,
            serverSnapshot: snapshot
        )
        updateFilename(fileId: fileId, filename: filename)
    }

    func enqueueDelete(fileId: String) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let operationId = UUID().uuidString
        let payload = IngestionOperationPayload(
            operationId: operationId,
            op: "delete",
            id: fileId,
            clientUpdatedAt: fileMeta(for: fileId)?.updatedAt
        )
        let snapshot = makeServerSnapshot(fileId: fileId)
        try await writeQueue.enqueue(
            operation: .delete,
            entityType: .file,
            entityId: fileId,
            payload: payload,
            serverSnapshot: snapshot
        )
        removeItem(fileId: fileId)
    }

    func applySyncFile(_ file: IngestedFileMeta) {
        if file.deletedAt != nil {
            removeItem(fileId: file.id)
            return
        }
        if let index = remoteItems.firstIndex(where: { $0.file.id == file.id }) {
            let existing = remoteItems[index]
            remoteItems[index] = IngestionListItem(
                file: mergeFile(existing: existing.file, incoming: file),
                job: existing.job,
                recommendedViewer: existing.recommendedViewer
            )
        } else if let local = localItems[file.id] {
            remoteItems.append(
                IngestionListItem(
                    file: mergeFile(existing: local.file, incoming: file),
                    job: local.job,
                    recommendedViewer: local.recommendedViewer
                )
            )
        } else {
            let job = IngestionJob(
                status: nil,
                stage: nil,
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 0,
                updatedAt: nil
            )
            remoteItems.append(
                IngestionListItem(
                    file: file,
                    job: job,
                    recommendedViewer: nil
                )
            )
        }
        if let meta = activeMeta, meta.file.id == file.id {
            let updatedMeta = IngestionMetaResponse(
                file: mergeFile(existing: meta.file, incoming: file),
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
            let lastSyncAt = Date()
            offlineStore?.set(
                key: CacheKeys.ingestionMeta(fileId: updatedMeta.file.id),
                entityType: "file",
                value: updatedMeta,
                lastSyncAt: lastSyncAt
            )
        }
        items = mergeItems(remoteItems)
        persistListCache()
    }

    private func fileMeta(for fileId: String) -> IngestedFileMeta? {
        if let item = items.first(where: { $0.file.id == fileId }) {
            return item.file
        }
        if let meta = activeMeta, meta.file.id == fileId {
            return meta.file
        }
        if let local = localItems[fileId] {
            return local.file
        }
        return nil
    }

    private func mergeFile(existing: IngestedFileMeta, incoming: IngestedFileMeta) -> IngestedFileMeta {
        IngestedFileMeta(
            id: existing.id,
            filenameOriginal: incoming.filenameOriginal,
            path: incoming.path ?? existing.path,
            mimeOriginal: existing.mimeOriginal,
            sizeBytes: existing.sizeBytes,
            sha256: existing.sha256,
            pinned: incoming.pinned ?? existing.pinned,
            pinnedOrder: incoming.pinnedOrder ?? existing.pinnedOrder,
            category: existing.category,
            sourceUrl: incoming.sourceUrl ?? existing.sourceUrl,
            sourceMetadata: incoming.sourceMetadata ?? existing.sourceMetadata,
            createdAt: existing.createdAt,
            updatedAt: incoming.updatedAt ?? existing.updatedAt,
            deletedAt: incoming.deletedAt ?? existing.deletedAt
        )
    }

    private func makeServerSnapshot(fileId: String) -> ServerSnapshot? {
        guard let file = fileMeta(for: fileId) else { return nil }
        let snapshot = FileSnapshot(
            filenameOriginal: file.filenameOriginal,
            pinned: file.pinned,
            pinnedOrder: file.pinnedOrder,
            path: file.path
        )
        return ServerSnapshot(
            entityType: .file,
            entityId: fileId,
            capturedAt: Date(),
            payload: .file(snapshot)
        )
    }
}
