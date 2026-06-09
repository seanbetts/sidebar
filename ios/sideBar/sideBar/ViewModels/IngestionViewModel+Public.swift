import Combine
import sideBarShared
import Foundation
import UniformTypeIdentifiers

// MARK: - IngestionViewModel+Public
extension IngestionViewModel {
    public func load(force: Bool = false) async {
        if items.isEmpty { isLoading = true }
        ContentListReadRecovery.begin(hasVisibleContent: !items.isEmpty)
            .apply(errorMessage: &errorMessage, loadState: &listLoadState)
        do {
            try await store.loadList(force: force)
            ContentListReadRecovery.success()
                .apply(errorMessage: &errorMessage, loadState: &listLoadState)
        } catch {
            if let failureTransition = ContentListReadRecovery.failure(
                error: error,
                hasVisibleContent: !items.isEmpty,
                mapError: { ingestionErrorMessage(for: $0, operation: "ingestion.list", requestKind: .foregroundRead) }
            ) {
                failureTransition.apply(errorMessage: &errorMessage, loadState: &listLoadState)
            }
        }
        isLoading = false
    }

    public func loadMeta(fileId: String, force: Bool = false) async -> Bool {
        errorMessage = nil
        if !force,
           !(networkStatus?.offlineCapabilityPolicy.canAttemptServerRead ?? true),
           !store.hasCachedMeta(fileId: fileId) {
            errorMessage = "This file isn't available offline yet."
            return false
        }
        do {
            try await store.loadMeta(fileId: fileId, force: force)
            if let meta = activeMeta, meta.file.id == fileId {
                store.updateFilename(fileId: fileId, filename: meta.file.filenameOriginal)
                store.updateJob(fileId: fileId, job: meta.job, recommendedViewer: meta.recommendedViewer)
            }
            if force {
                cancelJobPolling(fileId: fileId)
            }
            startJobPollingIfNeeded(fileId: fileId)
            await ensureViewerReady(for: fileId)
            return true
        } catch {
            errorMessage = ingestionErrorMessage(
                for: error,
                operation: "ingestion.meta",
                requestKind: .foregroundRead
            )
            return false
        }
    }

    @discardableResult
    public func selectFile(fileId: String, forceRefresh: Bool = false) async -> Bool {
        prepareSelection(fileId: fileId)
        if !forceRefresh,
           !(networkStatus?.offlineCapabilityPolicy.canAttemptServerRead ?? true),
           !store.hasCachedMeta(fileId: fileId) {
            errorMessage = "This file isn't available offline yet."
            return false
        }
        isSelecting = true
        defer { isSelecting = false }
        let didLoadMeta = await loadMeta(fileId: fileId, force: forceRefresh)
        guard didLoadMeta else { return false }
        guard let meta = activeMeta else { return false }
        guard viewerState == nil else { return true }
        startJobPollingIfNeeded(fileId: fileId)
        if let kind = preferredDerivativeKind(for: meta) {
            await selectDerivative(kind: kind)
        }
        return true
    }

    public func prepareSelection(fileId: String) {
        if let selectedFileId, selectedFileId != fileId {
            cancelJobPolling(fileId: selectedFileId)
        }
        if activeMeta?.file.id != fileId {
            store.clearActiveMeta()
        }
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
        do {
            try await store.enqueuePin(fileId: fileId, pinned: pinned)
        } catch WriteQueueError.queueFull {
            presentMutationFailureMessage("Sync queue full. Review pending changes.")
        } catch {
            presentMutationFailureMessage("Failed to queue file update")
        }
    }

    public func reorderPinnedFiles(ids: [String]) async -> Bool {
        let previousOrder = store.pinnedFileOrder()
        guard ids.count == previousOrder.count, Set(ids) == Set(previousOrder) else {
            return false
        }
        do {
            try await store.enqueuePinnedOrder(ids: ids)
            return true
        } catch WriteQueueError.queueFull {
            presentMutationFailureMessage("Sync queue full. Review pending changes.")
            return false
        } catch {
            presentMutationFailureMessage("Failed to queue pinned order")
            return false
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
        do {
            try await store.enqueueDelete(fileId: fileId)
            if selectedFileId == fileId {
                clearSelection()
            }
            return true
        } catch WriteQueueError.queueFull {
            presentMutationFailureMessage("Sync queue full. Review pending changes.")
        } catch {
            presentMutationFailureMessage("Failed to queue file delete")
        }
        return false
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
        do {
            try await store.enqueueRename(fileId: fileId, filename: filename)
            items = store.items
            activeMeta = store.activeMeta
            return true
        } catch WriteQueueError.queueFull {
            presentMutationFailureMessage("Sync queue full. Review pending changes.")
        } catch {
            presentMutationFailureMessage("Failed to queue file rename")
        }
        return false
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
            registerFileJobProgress(fileId: fileId)
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
            return youTubeIngestionFailureMessage(for: error)
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
        guard FileJobStatusPolicy.isActive(item.statusValue) else { return false }
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
        guard items.contains(where: { $0.file.id == fileId }) else { return }
        guard canCancelIngestion(fileId: fileId) else { return }

        if fileId.hasPrefix("local-") {
            cancelUpload(fileId: fileId)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.cancelHeaderIngestion(fileId: fileId)
            } catch {
                self.toastCenter.show(
                    message: self.ingestionErrorMessage(
                        for: error,
                        operation: "ingestion.cancel",
                        requestKind: .foregroundMutation
                    )
                )
            }
        }
    }

    public var selectedItem: IngestionListItem? {
        guard let selectedFileId else { return nil }
        return items.first { $0.file.id == selectedFileId }
    }

    public var activeUploadItems: [IngestionListItem] {
        items.filter { FileJobStatusPolicy.isActive($0.statusValue) }
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

    private func ingestionErrorMessage(
        for error: Error,
        operation: String,
        requestKind: RequestKind?
    ) -> String {
        ErrorMapping.presentation(
            for: error,
            operation: operation,
            requestKind: requestKind
        ).message
    }

    private func youTubeIngestionFailureMessage(for error: Error) -> String {
        guard let apiError = error as? APIClientError else { return "Failed to add YouTube video" }
        switch apiError {
        case .appError(let appError) where [.requestRejected, .payloadTooLarge].contains(appError.category):
            return ErrorMapping.message(for: appError)
        case .apiError(let message):
            return ErrorMapping.message(for: APIClientError.apiError(message))
        default:
            return "Failed to add YouTube video"
        }
    }

    private func retryableYouTubeSource(for item: IngestionListItem) -> String? {
        guard item.file.id.hasPrefix("youtube-") else { return nil }
        guard let sourceUrl = item.file.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        guard !sourceUrl.isEmpty else { return nil }
        return sourceUrl
    }

    func refreshWidgetData() async {
        do {
            try await store.loadList(force: true)
        } catch {
            // Silently fail - widget will use cached data
        }
    }
}
