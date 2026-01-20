import Combine
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
                errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
        store.updatePinned(fileId: fileId, pinned: pinned)
        do {
            try await api.pin(fileId: fileId, pinned: pinned)
        } catch {
            if let previousPinned {
                store.updatePinned(fileId: fileId, pinned: previousPinned)
            }
            errorMessage = error.localizedDescription
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
        if selectedFileId == fileId {
            clearSelection()
        }
        store.removeItem(fileId: fileId)
        do {
            try await api.delete(fileId: fileId)
            return true
        } catch {
            await load(force: true)
            return false
        }
    }

    public func renameFile(fileId: String, filename: String) async -> Bool {
        do {
            try await api.rename(fileId: fileId, filename: filename)
            store.updateFilename(fileId: fileId, filename: filename)
            return true
        } catch {
            return false
        }
    }

    public func addUploads(urls: [URL]) {
        for url in urls {
            startUpload(url: url)
        }
    }

    public func ingestYouTube(url: String) async -> String? {
        let trimmed = url.trimmed
        guard let normalized = normalizeYouTubeUrlCandidate(trimmed) else {
            return "Invalid YouTube URL"
        }
        isIngestingYouTube = true
        defer { isIngestingYouTube = false }
        let tempId = "youtube-\(UUID().uuidString)"
        let pendingItem = makeLocalItem(
            id: tempId,
            filename: "YouTube Video",
            mimeType: "video/youtube",
            sizeBytes: 0,
            status: "processing",
            stage: "queued",
            progress: nil,
            sourceUrl: normalized
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
}
