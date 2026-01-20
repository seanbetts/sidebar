import Combine
import Foundation
import UniformTypeIdentifiers

// MARK: - IngestionViewModel+Private

extension IngestionViewModel {
    private func preferredDerivativeKind(for meta: IngestionMetaResponse) -> String? {
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

    private func ensureViewerReady(for fileId: String) async {
        guard selectedFileId == fileId else { return }
        guard let meta = activeMeta else { return }
        guard viewerState == nil else { return }
        guard (meta.job.status ?? "") == "ready" else { return }
        if let kind = preferredDerivativeKind(for: meta) {
            await selectDerivative(kind: kind)
        }
    }

    private func startJobPollingIfNeeded(fileId: String) {
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

    private func cancelJobPolling(fileId: String? = nil) {
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

    private func updateListPollingState(items: [IngestionListItem]) {
        if items.hasActiveItems {
            startListPolling()
        } else {
            stopListPolling()
        }
    }

    private func startListPolling() {
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

    private func stopListPolling() {
        listPollingTask?.cancel()
        listPollingTask = nil
    }

    private func detectReadyTransitions(items: [IngestionListItem]) {
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

    private func registerReadyMessage(_ notification: ReadyFileNotification) {
        lastReadyMessage = notification
        readyMessageTask.runDebounced(delay: 6) { [weak self] in
            await MainActor.run {
                if self?.lastReadyMessage?.id == notification.id {
                    self?.lastReadyMessage = nil
                }
            }
        }
    }

    private func loadDerivativeContent(meta: IngestionMetaResponse, derivative: IngestionDerivative) async {
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
                let rawText = String(decoding: data, as: UTF8.self)
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

    private func startUpload(url: URL) {
        let filename = url.lastPathComponent
        let mimeType = mimeTypeFor(url: url)
        let tempId = "local-\(UUID().uuidString)"
        let access = url.startAccessingSecurityScopedResource()
        if access {
            securityScopedURLs[tempId] = url
        }
        let sizeBytes = fileSizeBytes(for: url)
        let item = makeLocalItem(
            id: tempId,
            filename: filename,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            status: "uploading",
            stage: "uploading",
            progress: 0,
            sourceUrl: nil
        )
        store.addLocalUpload(item)
        prepareSelection(fileId: tempId)

        uploadManager.startUpload(
            uploadId: tempId,
            fileURL: url,
            filename: filename,
            mimeType: mimeType,
            folder: "",
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

    private func handleUploadCompletion(
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

    private func makeLocalItem(
        id: String,
        filename: String,
        mimeType: String,
        sizeBytes: Int,
        status: String,
        stage: String,
        progress: Double?,
        sourceUrl: String?
    ) -> IngestionListItem {
        let file = IngestedFileMeta(
            id: id,
            filenameOriginal: filename,
            path: nil,
            mimeOriginal: mimeType,
            sizeBytes: sizeBytes,
            sha256: nil,
            pinned: false,
            pinnedOrder: nil,
            category: nil,
            sourceUrl: sourceUrl,
            sourceMetadata: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        let job = IngestionJob(
            status: status,
            stage: stage,
            errorCode: nil,
            errorMessage: nil,
            userMessage: nil,
            progress: progress,
            attempts: 0,
            updatedAt: nil
        )
        return IngestionListItem(file: file, job: job, recommendedViewer: nil)
    }

    private func mimeTypeFor(url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    private func fileSizeBytes(for url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private func normalizeYouTubeUrlCandidate(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let candidate = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: candidate),
              let host = url.host?.lowercased(),
              host.contains("youtube.com") || host.contains("youtu.be") else {
            return nil
        }
        return candidate
    }

    private func releaseSecurityScopedAccess(for fileId: String) {
        guard let url = securityScopedURLs.removeValue(forKey: fileId) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    private func makeFilename(base: String, mimeType: String, fallback: String) -> String {
        if base.contains(".") {
            return base
        }
        if let ext = filenameExtension(for: mimeType) {
            return "\(base).\(ext)"
        }
        return "\(base)-\(fallback)"
    }

    private func filenameExtension(for mimeType: String) -> String? {
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

    private func overrideKindIfMarkdown(
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

    private func buildYouTubeEmbedURL(from file: IngestedFileMeta) -> URL? {
        if let metadata = file.sourceMetadata {
            if let value = metadata["video_id"]?.value as? String {
                return makeYouTubeEmbedURL(videoId: value)
            }
            if let value = metadata["youtube_url"]?.value as? String,
               let videoId = extractYouTubeVideoId(from: value) {
                return makeYouTubeEmbedURL(videoId: videoId)
            }
        }
        if let raw = file.sourceUrl,
           let videoId = extractYouTubeVideoId(from: raw) {
            return makeYouTubeEmbedURL(videoId: videoId)
        }
        return nil
    }

    private func makeYouTubeEmbedURL(videoId: String) -> URL? {
        guard let trimmed = videoId.trimmedOrNil else { return nil }
        let url = "https://www.youtube-nocookie.com/embed/\(trimmed)?playsinline=1&rel=0&modestbranding=1&origin=https://www.youtube-nocookie.com"
        return URL(string: url)
    }

    private func extractYouTubeVideoId(from raw: String) -> String? {
}
