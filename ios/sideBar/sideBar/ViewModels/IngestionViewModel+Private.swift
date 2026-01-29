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
        jobPollingTasks[fileId] = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard self.selectedFileId == fileId else {
                    self.cancelJobPolling(fileId: fileId)
                    return
                }
                do {
                    try await self.store.loadMeta(fileId: fileId, force: true)
                    if let meta = self.activeMeta, meta.file.id == fileId {
                        self.store.updateJob(fileId: fileId, job: meta.job, recommendedViewer: meta.recommendedViewer)
                        if (meta.job.status ?? "") == "ready" {
                            await self.ensureViewerReady(for: fileId)
                            self.cancelJobPolling(fileId: fileId)
                            return
                        }
                        if (meta.job.status ?? "") == "failed" {
                            self.cancelJobPolling(fileId: fileId)
                            return
                        }
                    }
                } catch {
                    // Ignore polling errors; next tick will retry.
                }
            }
        }
    }

    func cancelJobPolling(fileId: String? = nil) {
        if let fileId {
            jobPollingTasks[fileId]?.cancel()
            jobPollingTasks[fileId] = nil
            return
        }
        for task in jobPollingTasks.values {
            task.cancel()
        }
        jobPollingTasks = [:]
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
                viewerState = FileViewerState(
                    title: meta.file.filenameOriginal,
                    kind: kind,
                    text: nil,
                    fileURL: fileURL,
                    spreadsheet: nil,
                    youtubeEmbedURL: youtubeEmbedURL
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingContent = false
    }

    func startUpload(url: URL) {
        let filename = url.lastPathComponent
        let mimeType = mimeTypeFor(url: url)
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
            createdAt: ISO8601DateFormatter().string(from: Date())
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

    func mimeTypeFor(url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    func fileSizeBytes(for url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    func normalizeYouTubeUrlCandidate(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let candidate = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: candidate),
              let host = url.host?.lowercased(),
              host.contains("youtube.com") || host.contains("youtu.be") else {
            return nil
        }
        return candidate
    }

    func releaseSecurityScopedAccess(for fileId: String) {
        guard let url = securityScopedURLs.removeValue(forKey: fileId) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    func makeBookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    func makeFilename(base: String, mimeType: String, fallback: String) -> String {
        if base.contains(".") {
            return base
        }
        if let ext = filenameExtension(for: mimeType) {
            return "\(base).\(ext)"
        }
        return "\(base)-\(fallback)"
    }

    func filenameExtension(for mimeType: String) -> String? {
        let normalized = mimeType.lowercased()
        switch normalized {
        case "application/pdf":
            return "pdf"
        case "application/json":
            return "json"
        case "text/markdown":
            return "md"
        case "text/plain":
            return "txt"
        case "text/csv":
            return "csv"
        case "text/tab-separated-values":
            return "tsv"
        default:
            if normalized.hasPrefix("image/") {
                return normalized.replacingOccurrences(of: "image/", with: "")
            }
            if normalized.hasPrefix("audio/") {
                return normalized.replacingOccurrences(of: "audio/", with: "")
            }
            if normalized.hasPrefix("video/") {
                return normalized.replacingOccurrences(of: "video/", with: "")
            }
            return nil
        }
    }

    func overrideKindIfMarkdown(
        inferredKind: FileViewerKind,
        filename: String,
        mimeType: String
    ) -> FileViewerKind {
        if inferredKind == .text {
            let lower = filename.lowercased()
            if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
                return .markdown
            }
            if mimeType.lowercased() == "text/markdown" {
                return .markdown
            }
        }
        return inferredKind
    }

}
