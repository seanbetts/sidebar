import Foundation

// MARK: - Realtime + Local Updates

extension IngestionStore {
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
            let updated = IngestionListItem(
                file: local.file,
                job: job,
                recommendedViewer: local.recommendedViewer
            )
            setLocalUpload(item: updated, bookmarkData: nil)
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
            let updated = IngestionListItem(
                file: updatedFile,
                job: local.job,
                recommendedViewer: local.recommendedViewer
            )
            setLocalUpload(item: updated, bookmarkData: nil)
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
            let updated = IngestionListItem(
                file: updatedFile,
                job: local.job,
                recommendedViewer: local.recommendedViewer
            )
            setLocalUpload(item: updated, bookmarkData: nil)
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
            let updated = IngestionListItem(
                file: local.file,
                job: job,
                recommendedViewer: recommendedViewer ?? local.recommendedViewer
            )
            setLocalUpload(item: updated, bookmarkData: nil)
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

    public func removeItem(fileId: String) {
        remoteItems.removeAll { $0.file.id == fileId }
        removeLocalUploadRecord(fileId: fileId)
        items = mergeItems(remoteItems)
        if activeMeta?.file.id == fileId {
            activeMeta = nil
        }
        persistListCache()
        cache.remove(key: CacheKeys.ingestionMeta(fileId: fileId))
        offlineStore?.remove(key: CacheKeys.ingestionMeta(fileId: fileId))
    }

    public func addLocalUpload(_ item: IngestionListItem) {
        setLocalUpload(item: item, bookmarkData: nil)
        items = mergeItems(remoteItems)
    }

    public func addLocalUpload(_ item: IngestionListItem, bookmarkData: Data?) {
        setLocalUpload(item: item, bookmarkData: bookmarkData)
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
        let updated = IngestionListItem(
            file: existing.file,
            job: updatedJob,
            recommendedViewer: existing.recommendedViewer
        )
        setLocalUpload(item: updated, bookmarkData: nil)
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
        removeLocalUploadRecord(fileId: tempId)
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
            createdAt: existing.file.createdAt,
            updatedAt: existing.file.updatedAt,
            deletedAt: existing.file.deletedAt
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
        let updated = IngestionListItem(
            file: updatedFile,
            job: updatedJob,
            recommendedViewer: existing.recommendedViewer
        )
        setLocalUpload(item: updated, bookmarkData: nil)
        items = mergeItems(remoteItems)
    }

    public func removeLocalUpload(fileId: String) {
        removeLocalUploadRecord(fileId: fileId)
        items = mergeItems(remoteItems)
    }

    func pendingUploadsForResume() -> [LocalUploadResumeItem] {
        localUploadRecords.values.compactMap { record in
            guard let bookmarkData = record.bookmarkData else { return nil }
            let status = record.item.job.status ?? ""
            guard status == "uploading" || status == "queued" else { return nil }
            return LocalUploadResumeItem(item: record.item, bookmarkData: bookmarkData)
        }
    }
}
