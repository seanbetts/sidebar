import Combine
import sideBarShared
import Foundation
import UniformTypeIdentifiers

// MARK: - IngestionViewModel+Private

extension IngestionViewModel {
    func preferredDerivativeKind(for meta: IngestionMetaResponse) -> String? {
        let candidates = meta.derivatives.filter { $0.kind != "thumb_png" }
        let nonAI = candidates.filter { $0.kind != "ai_md" }

        if let recommended = meta.recommendedViewer {
            if recommended == "ai_md" {
                return nonAI.first?.kind ?? "ai_md"
            }
            if recommended == "viewer_video",
               meta.derivatives.contains(where: { $0.kind == "video_original" }) {
                return "video_original"
            }
            if meta.derivatives.contains(where: { $0.kind == recommended }) {
                return recommended
            }
        }
        return nonAI.first?.kind ?? candidates.first?.kind
    }

    func preferredDownloadDerivative(for meta: IngestionMetaResponse) -> IngestionDerivative? {
        if let sourceOriginal = meta.derivatives.first(where: { $0.kind == "source_original" }) {
            return sourceOriginal
        }
        if let selectedKind = selectedDerivativeKind,
           let selected = meta.derivatives.first(where: { $0.kind == selectedKind }) {
            return selected
        }
        if let preferredKind = preferredDerivativeKind(for: meta),
           let preferred = meta.derivatives.first(where: { $0.kind == preferredKind }) {
            return preferred
        }
        return meta.derivatives.first
    }

    func ensureViewerReady(for fileId: String) async {
        guard selectedFileId == fileId else { return }
        guard let meta = activeMeta else { return }
        guard viewerState == nil else { return }
        guard (meta.job.status ?? "") == "ready" else { return }
        if let kind = preferredDerivativeKind(for: meta) {
            await selectDerivative(kind: kind)
        }
    }

    func startJobPollingIfNeeded(fileId: String) {
        guard let meta = activeMeta, meta.file.id == fileId else { return }
        let status = meta.job.status ?? ""
        guard status != "ready" && status != "failed" && status != "canceled" else {
            cancelJobPolling(fileId: fileId)
            return
        }
        guard jobPollingTasks[fileId] == nil else { return }
        let token = UUID()
        jobPollingTaskTokens[fileId] = token
        jobPollingTasks[fileId] = makeJobPollingTask(fileId: fileId, token: token)
    }

    func cancelJobPolling(fileId: String? = nil) {
        if let fileId {
            jobPollingTasks[fileId]?.cancel()
            jobPollingTasks[fileId] = nil
            jobPollingTaskTokens[fileId] = nil
            return
        }
        for task in jobPollingTasks.values {
            task.cancel()
        }
        jobPollingTasks = [:]
        jobPollingTaskTokens = [:]
    }

    private func finishJobPolling(fileId: String, token: UUID) {
        guard jobPollingTaskTokens[fileId] == token else { return }
        jobPollingTasks[fileId] = nil
        jobPollingTaskTokens[fileId] = nil
    }

    private func makeJobPollingTask(fileId: String, token: UUID) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.finishJobPolling(fileId: fileId, token: token)
                }
            }
            var consecutiveFailures = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: self.jobPollingDelayNanoseconds(
                            fileId: fileId,
                            consecutiveFailures: consecutiveFailures
                        )
                    )
                } catch {
                    return
                }
                guard self.selectedFileId == fileId else {
                    return
                }
                do {
                    let terminal = try await self.pollJobStatus(fileId: fileId)
                    if terminal {
                        return
                    }
                    consecutiveFailures = 0
                } catch {
                    consecutiveFailures += 1
                    guard consecutiveFailures >= self.jobPollingMaxConsecutiveFailures else {
                        continue
                    }
                    self.markJobPollingFailed(fileId: fileId)
                    return
                }
            }
        }
    }

    private func pollJobStatus(fileId: String) async throws -> Bool {
        try await store.loadMeta(fileId: fileId, force: true)
        guard let meta = activeMeta, meta.file.id == fileId else {
            return false
        }
        store.updateJob(fileId: fileId, job: meta.job, recommendedViewer: meta.recommendedViewer)
        let status = (meta.job.status ?? "").lowercased()
        if status == "ready" {
            await ensureViewerReady(for: fileId)
            return true
        }
        return status == "failed" || status == "canceled"
    }

    private func markJobPollingFailed(fileId: String) {
        let message = "Could not refresh file status. Re-open the file to retry."
        errorMessage = message
        store.updateLocalUpload(
            fileId: fileId,
            status: "failed",
            stage: "failed",
            progress: nil,
            errorMessage: message
        )
    }

    func updateListPollingState(items: [IngestionListItem]) {
        if items.hasActiveItems {
            startListPolling()
        } else {
            stopListPolling()
        }
    }

    func startListPolling() {
        guard listPollingTask == nil else { return }
        let task = PollingTask(interval: 3)
        listPollingTask = task
        task.start { [weak self] in
            do {
                try await self?.store.loadList(force: true)
            } catch {
                // Ignore polling errors; next tick will retry.
            }
        }
    }

    func stopListPolling() {
        listPollingTask?.cancel()
        listPollingTask = nil
    }

    func detectReadyTransitions(items: [IngestionListItem]) {
        var seenIds = Set<String>()
        for item in items {
            let fileId = item.file.id
            seenIds.insert(fileId)
            let status = item.job.status ?? ""
            if let previous = statusCache[fileId],
               previous != status,
               status == "ready" {
                let notification = ReadyFileNotification(
                    fileId: fileId,
                    filename: item.file.filenameOriginal
                )
                readyFileNotification = notification
                registerReadyMessage(notification)
            }
            statusCache[fileId] = status
        }
        statusCache.keys.filter { !seenIds.contains($0) }.forEach { statusCache.removeValue(forKey: $0) }
    }

    func registerReadyMessage(_ notification: ReadyFileNotification) {
        lastReadyMessage = notification
        readyMessageTask.runDebounced(delay: 6) { [weak self] in
            guard let self, self.lastReadyMessage?.id == notification.id else {
                return
            }
            self.lastReadyMessage = nil
        }
    }

    func loadDerivativeContent(meta: IngestionMetaResponse, derivative: IngestionDerivative) async {
        isLoadingContent = true
        errorMessage = nil
        do {
            let data = try await api.getContent(fileId: meta.file.id, kind: derivative.kind, range: nil)
            let inferredKind = FileViewerKind.infer(path: nil, mimeType: derivative.mime, derivativeKind: derivative.kind)
            let kind = overrideKindIfMarkdown(
                inferredKind: inferredKind,
                filename: meta.file.filenameOriginal,
                mimeType: derivative.mime
            )
            let filename = makeFilename(base: meta.file.filenameOriginal, mimeType: derivative.mime, fallback: derivative.kind)
            let youtubeEmbedURL = buildYouTubeEmbedURL(from: meta.file)
            switch kind {
            case .markdown, .text, .json:
                let rawText = String(bytes: data, encoding: .utf8) ?? ""
                let shouldStrip = derivative.kind == "ai_md" || kind == .markdown
                let text = shouldStrip ? MarkdownRendering.stripFrontmatter(rawText) : rawText
                let fileURL = try temporaryStore.store(data: data, filename: filename)
                viewerState = FileViewerState(
                    title: meta.file.filenameOriginal,
                    kind: kind,
                    text: text,
                    fileURL: fileURL,
                    spreadsheet: nil,
                    youtubeEmbedURL: youtubeEmbedURL
                )
            case .spreadsheet:
                let spreadsheet = try? JSONDecoder().decode(SpreadsheetPayload.self, from: data)
                let fileURL = try temporaryStore.store(data: data, filename: filename)
                viewerState = FileViewerState(
                    title: meta.file.filenameOriginal,
                    kind: .spreadsheet,
                    text: nil,
                    fileURL: fileURL,
                    spreadsheet: spreadsheet,
                    youtubeEmbedURL: youtubeEmbedURL
                )
            default:
                let fileURL = try temporaryStore.store(data: data, filename: filename)
                let transcript = await transcriptForVideoIfAvailable(
                    meta: meta,
                    kind: kind
                )
                viewerState = FileViewerState(
                    title: meta.file.filenameOriginal,
                    kind: kind,
                    text: transcript,
                    fileURL: fileURL,
                    spreadsheet: nil,
                    youtubeEmbedURL: youtubeEmbedURL
                )
            }
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
        isLoadingContent = false
    }

    private func jobPollingDelayNanoseconds(fileId: String, consecutiveFailures: Int) -> UInt64 {
        let exponent = min(max(consecutiveFailures, 0), 4)
        let scaled = min(
            jobPollingBaseInterval * pow(2, Double(exponent)),
            jobPollingMaxInterval
        )
        let jitter = deterministicJitter(
            seed: "ingestion:\(fileId)",
            attempt: consecutiveFailures,
            maxValue: jobPollingJitterWindow
        )
        return UInt64((scaled + jitter) * 1_000_000_000)
    }

    private func deterministicJitter(seed: String, attempt: Int, maxValue: TimeInterval) -> TimeInterval {
        guard maxValue > 0 else { return 0 }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(seed):\(attempt)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let bucket = Double(hash % 1_000) / 1_000
        return bucket * maxValue
    }

    func startUpload(url: URL) {
        let filename = url.lastPathComponent
        let mimeType = mimeTypeFor(url: url)
        if isOfflineForIngestion() {
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let queued = pendingShareStore.enqueueFile(
                at: url,
                filename: filename,
                mimeType: mimeType,
                kind: .file
            )
            if queued != nil {
                toastCenter.show(message: "Saved for later", style: .success)
            } else {
                toastCenter.show(message: "Could not save for later")
            }
            return
        }
        let tempId = "local-\(UUID().uuidString)"
        let access = url.startAccessingSecurityScopedResource()
        if access {
            securityScopedURLs[tempId] = url
        }
        let bookmarkData = makeBookmarkData(for: url)
        let sizeBytes = fileSizeBytes(for: url)
        let item = makeLocalItem(
            input: LocalIngestionItemInput(
                id: tempId,
                filename: filename,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                status: "uploading",
                stage: "uploading",
                progress: 0,
                sourceUrl: nil
            )
        )
        store.addLocalUpload(item, bookmarkData: bookmarkData)
        prepareSelection(fileId: tempId)

        uploadManager.startUpload(
            request: UploadRequest(
                uploadId: tempId,
                fileURL: url,
                filename: filename,
                mimeType: mimeType,
                folder: ""
            ),
            onProgress: { [weak self] progress in
                guard let self else { return }
                self.store.updateLocalUpload(
                    fileId: tempId,
                    status: "uploading",
                    stage: "uploading",
                    progress: progress
                )
            },
            onCompletion: { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleUploadCompletion(
                        tempId: tempId,
                        filename: filename,
                        mimeType: mimeType,
                        sizeBytes: sizeBytes,
                        result: result
                    )
                }
            }
        )
    }

    func isOfflineForIngestion() -> Bool {
        if let networkStatus {
            if networkStatus.isOffline || !networkStatus.isNetworkAvailable {
                return true
            }
        }
        return store.isOffline
    }

    func resumeUpload(_ record: LocalUploadResumeItem) {
        let fileId = record.item.file.id
        guard let url = resolveBookmark(record.bookmarkData) else {
            store.updateLocalUpload(fileId: fileId, status: "failed", stage: "failed", progress: nil)
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        if access {
            securityScopedURLs[fileId] = url
        }
        store.updateLocalUpload(fileId: fileId, status: "uploading", stage: "uploading", progress: 0)
        uploadManager.startUpload(
            request: UploadRequest(
                uploadId: fileId,
                fileURL: url,
                filename: record.item.file.filenameOriginal,
                mimeType: record.item.file.mimeOriginal,
                folder: ""
            ),
            onProgress: { [weak self] progress in
                self?.store.updateLocalUpload(
                    fileId: fileId,
                    status: "uploading",
                    stage: "uploading",
                    progress: progress
                )
            },
            onCompletion: { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleUploadCompletion(
                        tempId: fileId,
                        filename: record.item.file.filenameOriginal,
                        mimeType: record.item.file.mimeOriginal,
                        sizeBytes: record.item.file.sizeBytes,
                        result: result
                    )
                }
            }
        )
    }

    func handleUploadCompletion(
        tempId: String,
        filename: String,
        mimeType: String,
        sizeBytes: Int,
        result: Result<String, Error>
    ) async {
        switch result {
        case .success(let fileId):
            releaseSecurityScopedAccess(for: tempId)
            store.replaceLocalUpload(
                tempId: tempId,
                fileId: fileId,
                filename: filename,
                mimeType: mimeType,
                sizeBytes: sizeBytes
            )
            store.updateLocalUpload(
                fileId: fileId,
                status: "processing",
                stage: "processing",
                progress: nil
            )
            if selectedFileId == tempId {
                prepareSelection(fileId: fileId)
            }
            await selectFile(fileId: fileId)
        case .failure:
            releaseSecurityScopedAccess(for: tempId)
            store.updateLocalUpload(fileId: tempId, status: "failed", stage: "failed", progress: nil)
        }
    }

    func makeLocalItem(input: LocalIngestionItemInput) -> IngestionListItem {
        let file = IngestedFileMeta(
            id: input.id,
            filenameOriginal: input.filename,
            path: nil,
            mimeOriginal: input.mimeType,
            sizeBytes: input.sizeBytes,
            sha256: nil,
            pinned: false,
            pinnedOrder: nil,
            category: nil,
            sourceUrl: input.sourceUrl,
            sourceMetadata: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: nil,
            deletedAt: nil
        )
        let job = IngestionJob(
            status: input.status,
            stage: input.stage,
            errorCode: nil,
            errorMessage: nil,
            userMessage: nil,
            progress: input.progress,
            attempts: 0,
            updatedAt: nil
        )
        return IngestionListItem(file: file, job: job, recommendedViewer: nil)
    }
}
