import Combine
import sideBarShared
import Foundation
import UniformTypeIdentifiers

// MARK: - IngestionViewModel+Public

extension IngestionViewModel {
    public func load(force: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            try await store.loadList(force: force)
        } catch {
            if items.isEmpty {
                errorMessage = ErrorMapping.message(for: error)
            }
        }
        isLoading = false
    }

    public func loadMeta(fileId: String, force: Bool = false) async {
        errorMessage = nil
        do {
            try await store.loadMeta(fileId: fileId, force: force)
            if let meta = activeMeta, meta.file.id == fileId {
                store.updateFilename(fileId: fileId, filename: meta.file.filenameOriginal)
                store.updateJob(fileId: fileId, job: meta.job, recommendedViewer: meta.recommendedViewer)
            }
            startJobPollingIfNeeded(fileId: fileId)
            await ensureViewerReady(for: fileId)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }

    public func selectFile(fileId: String, forceRefresh: Bool = false) async {
        isSelecting = true
        defer { isSelecting = false }
        prepareSelection(fileId: fileId)
        await loadMeta(fileId: fileId, force: forceRefresh)
        guard let meta = activeMeta else { return }
        guard viewerState == nil else { return }
        startJobPollingIfNeeded(fileId: fileId)
        if let kind = preferredDerivativeKind(for: meta) {
            await selectDerivative(kind: kind)
        }
    }

    public func prepareSelection(fileId: String) {
        selectedFileId = fileId
        viewerState = nil
        selectedDerivativeKind = nil
    }

    public func selectDerivative(kind: String) async {
        selectedDerivativeKind = kind
        guard let meta = activeMeta else { return }
        guard let derivative = meta.derivatives.first(where: { $0.kind == kind }) else { return }
        await loadDerivativeContent(meta: meta, derivative: derivative)
    }

    public func togglePinned(fileId: String, pinned: Bool) async {
        errorMessage = nil
        let previousPinned: Bool? = {
            if let item = items.first(where: { $0.file.id == fileId }) {
                return item.file.pinned
            }
            if let meta = activeMeta, meta.file.id == fileId {
                return meta.file.pinned
            }
            return nil
        }()
        if isOfflineForIngestion() {
            do {
                try await store.enqueuePin(fileId: fileId, pinned: pinned)
            } catch WriteQueueError.queueFull {
                if let previousPinned {
                    store.updatePinned(fileId: fileId, pinned: previousPinned)
                }
                errorMessage = "Sync queue full. Review pending changes."
            } catch {
                if let previousPinned {
                    store.updatePinned(fileId: fileId, pinned: previousPinned)
                }
                errorMessage = "Failed to queue file update"
            }
            return
        }
        store.updatePinned(fileId: fileId, pinned: pinned)
        do {
            try await api.pin(
                fileId: fileId,
                pinned: pinned,
                clientUpdatedAt: store.currentUpdatedAt(fileId: fileId)
            )
        } catch {
            if let previousPinned {
                store.updatePinned(fileId: fileId, pinned: previousPinned)
            }
            errorMessage = ErrorMapping.message(for: error)
        }
    }

    public func reorderPinnedFiles(ids: [String]) async -> Bool {
        guard !isOfflineForIngestion() else {
            return false
        }
        let previousOrder = store.pinnedFileOrder()
        guard ids.count == previousOrder.count, Set(ids) == Set(previousOrder) else {
            return false
        }
        store.applyPinnedOrder(ids)
        do {
            try await api.updatePinnedOrder(ids: ids)
            return true
        } catch {
            store.applyPinnedOrder(previousOrder)
            errorMessage = "Failed to reorder pinned files"
            return false
        }
    }

    public func applyIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>) async {
        store.applyIngestedFileEvent(payload)
        if let selectedFileId, selectedFileId == payload.record?.id || selectedFileId == payload.oldRecord?.id {
            await loadMeta(fileId: selectedFileId)
        }
    }

    public func applyFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) async {
        store.applyFileJobEvent(payload)
        if let selectedFileId, selectedFileId == payload.record?.fileId {
            await loadMeta(fileId: selectedFileId)
        }
    }

    public func clearSelection() {
        selectedFileId = nil
        store.clearActiveMeta()
        selectedDerivativeKind = nil
        viewerState = nil
        errorMessage = nil
        cancelJobPolling()
    }

    public func deleteFile(fileId: String) async -> Bool {
        if isOfflineForIngestion() {
            do {
                try await store.enqueueDelete(fileId: fileId)
                if selectedFileId == fileId {
                    clearSelection()
                }
                return true
            } catch WriteQueueError.queueFull {
                errorMessage = "Sync queue full. Review pending changes."
            } catch {
                errorMessage = "Failed to queue file delete"
            }
            return false
        }
        if selectedFileId == fileId {
            clearSelection()
        }
        let clientUpdatedAt = store.currentUpdatedAt(fileId: fileId)
        store.removeItem(fileId: fileId)
        do {
            try await api.delete(fileId: fileId, clientUpdatedAt: clientUpdatedAt)
            return true
        } catch {
            await load(force: true)
            return false
        }
    }

    public func clearFailedUpload(fileId: String) {
        guard let item = items.first(where: { $0.file.id == fileId }) else { return }
        guard (item.job.status ?? "") == "failed" else { return }
        if fileId.hasPrefix("local-") || fileId.hasPrefix("youtube-") {
            store.removeLocalUpload(fileId: fileId)
            if selectedFileId == fileId {
                clearSelection()
            }
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let didDelete = await deleteFile(fileId: fileId)
            if !didDelete {
                toastCenter.show(message: "Failed to clear failed upload")
            }
        }
    }

    public func retryFailedUpload(fileId: String) {
        guard let item = items.first(where: { $0.file.id == fileId }) else { return }
        guard [IngestionListItem].normalizedStatus(item.statusValue) == "failed" else { return }

        if let sourceUrl = retryableYouTubeSource(for: item) {
            store.removeLocalUpload(fileId: fileId)
            if selectedFileId == fileId {
                clearSelection()
            }
            Task { [weak self] in
                guard let self else { return }
                if let message = await self.ingestYouTube(url: sourceUrl, showQueuedToast: false) {
                    self.toastCenter.show(message: message)
                }
            }
            return
        }

        guard let resumable = retryableLocalUploadRecord(fileId: fileId) else {
            toastCenter.show(message: "Re-select file to retry upload")
            return
        }
        resumeUpload(resumable)
    }

    @discardableResult
    public func retryAllFailedUploads() -> Int {
        let failedIds = failedUploadItems.map(\.file.id)
        guard !failedIds.isEmpty else { return 0 }
        var retriedCount = 0
        for fileId in failedIds where canRetryFailedUpload(fileId: fileId) {
            retryFailedUpload(fileId: fileId)
            retriedCount += 1
        }
        if retriedCount == 0 {
            toastCenter.show(message: "No retryable uploads")
        }
        return retriedCount
    }

    public func canRetryFailedUpload(fileId: String) -> Bool {
        guard let item = items.first(where: { $0.file.id == fileId }) else { return false }
        guard [IngestionListItem].normalizedStatus(item.statusValue) == "failed" else { return false }
        if retryableYouTubeSource(for: item) != nil {
            return true
        }
        return retryableLocalUploadRecord(fileId: fileId) != nil
    }

    public func renameFile(fileId: String, filename: String) async -> Bool {
        if isOfflineForIngestion() {
            do {
                try await store.enqueueRename(fileId: fileId, filename: filename)
                return true
            } catch WriteQueueError.queueFull {
                errorMessage = "Sync queue full. Review pending changes."
            } catch {
                errorMessage = "Failed to queue file rename"
            }
            return false
        }
        let previousFilename = items.first(where: { $0.file.id == fileId })?.file.filenameOriginal
            ?? ((activeMeta?.file.id == fileId) ? activeMeta?.file.filenameOriginal : nil)
        store.updateFilename(fileId: fileId, filename: filename)
        items = store.items
        activeMeta = store.activeMeta
        do {
            try await api.rename(
                fileId: fileId,
                filename: filename,
                clientUpdatedAt: store.currentUpdatedAt(fileId: fileId)
            )
            return true
        } catch {
            if let previousFilename {
                store.updateFilename(fileId: fileId, filename: previousFilename)
                items = store.items
                activeMeta = store.activeMeta
            }
            return false
        }
    }

    public func addUploads(urls: [URL]) {
        for url in urls {
            startUpload(url: url)
        }
    }

    public func resumePendingUploads() {
        let pending = store.pendingUploadsForResume()
        guard !pending.isEmpty else { return }
        for record in pending {
            resumeUpload(record)
        }
    }

    public func ingestYouTube(url: String, showQueuedToast: Bool = true) async -> String? {
        let trimmed = url.trimmed
        guard let normalized = normalizeYouTubeUrlCandidate(trimmed) else {
            return "Invalid YouTube URL"
        }
        if isOfflineForIngestion() {
            if pendingShareStore.enqueueYouTube(url: normalized) != nil {
                if showQueuedToast {
                    toastCenter.show(message: "Saved for later", style: .success)
                }
                return nil
            }
            return "Could not save for later."
        }
        isIngestingYouTube = true
        defer { isIngestingYouTube = false }
        let tempId = "youtube-\(UUID().uuidString)"
        let pendingItem = makeLocalItem(
            input: LocalIngestionItemInput(
                id: tempId,
                filename: "YouTube Video",
                mimeType: "video/youtube",
                sizeBytes: 0,
                status: "processing",
                stage: "queued",
                progress: nil,
                sourceUrl: normalized
            )
        )
        store.addLocalUpload(pendingItem)
        prepareSelection(fileId: tempId)
        do {
            let fileId = try await api.ingestYouTube(url: normalized)
            store.replaceLocalUpload(
                tempId: tempId,
                fileId: fileId,
                filename: "YouTube Video",
                mimeType: "video/youtube",
                sizeBytes: 0,
                sourceUrl: normalized
            )
            store.updateLocalUpload(
                fileId: fileId,
                status: "processing",
                stage: "queued",
                progress: nil
            )
            if selectedFileId == tempId {
                prepareSelection(fileId: fileId)
            }
            await selectFile(fileId: fileId)
            startJobPollingIfNeeded(fileId: fileId)
            return nil
        } catch {
            store.updateLocalUpload(fileId: tempId, status: "failed", stage: "failed", progress: nil)
            if let apiError = error as? APIClientError {
                switch apiError {
                case .apiError(let message):
                    return message
                case .requestFailed:
                    return "Failed to add YouTube video"
                default:
                    return "Failed to add YouTube video"
                }
            }
            return "Failed to add YouTube video"
        }
    }

    public func cancelUpload(fileId: String) {
        uploadManager.cancelUpload(uploadId: fileId)
        store.updateLocalUpload(fileId: fileId, status: "canceled", stage: "canceled")
        store.removeLocalUpload(fileId: fileId)
        releaseSecurityScopedAccess(for: fileId)
    }

    public func canCancelIngestion(fileId: String) -> Bool {
        guard let item = items.first(where: { $0.file.id == fileId }) else { return false }
        let status = [IngestionListItem].normalizedStatus(item.statusValue)
        guard !status.isEmpty else { return false }
        guard ![IngestionListItem].terminalStatuses.contains(status) else { return false }
        if fileId.hasPrefix("youtube-") {
            // A temporary YouTube placeholder does not have a server-side job ID yet.
            return false
        }
        if fileId.hasPrefix("local-") {
            return true
        }
        guard IdentifierValidation.isServerFileID(fileId) else {
            return false
        }
        return true
    }

    public func cancelIngestion(fileId: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.cancelHeaderIngestion(fileId: fileId)
            } catch {
                self.toastCenter.show(message: error.localizedDescription)
            }
        }
    }

    public var selectedItem: IngestionListItem? {
        guard let selectedFileId else { return nil }
        return items.first { $0.file.id == selectedFileId }
    }

    public var activeUploadItems: [IngestionListItem] {
        items.activeItems
    }

    public var failedUploadItems: [IngestionListItem] {
        items.failedItems
    }

    public func clearReadyFileNotification() {
        readyFileNotification = nil
    }

    public func clearReadyMessage() {
        lastReadyMessage = nil
    }

    private func retryableLocalUploadRecord(fileId: String) -> LocalUploadResumeItem? {
        guard let record = store.localUploadRecords[fileId] else { return nil }
        guard let bookmarkData = record.bookmarkData else { return nil }
        return LocalUploadResumeItem(item: record.item, bookmarkData: bookmarkData)
    }

    private func retryableYouTubeSource(for item: IngestionListItem) -> String? {
        guard item.file.id.hasPrefix("youtube-") else { return nil }
        guard let sourceUrl = item.file.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        guard !sourceUrl.isEmpty else { return nil }
        return sourceUrl
    }

    /// Refreshes widget data by fetching the latest files list
    /// Called by background refresh task to keep widgets up-to-date
    func refreshWidgetData() async {
        do {
            try await store.loadList(force: true)
        } catch {
            // Silently fail - widget will use cached data
        }
    }
}
