// swiftlint:disable file_length
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
        let token = UUID()
        jobPollingTaskTokens[fileId] = token
        jobPollingTasks[fileId] = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.finishJobPolling(fileId: fileId, token: token)
                }
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard self.selectedFileId == fileId else {
                    return
                }
                do {
                    try await self.store.loadMeta(fileId: fileId, force: true)
                    if let meta = self.activeMeta, meta.file.id == fileId {
                        self.store.updateJob(fileId: fileId, job: meta.job, recommendedViewer: meta.recommendedViewer)
                        if (meta.job.status ?? "") == "ready" {
                            await self.ensureViewerReady(for: fileId)
                            return
                        }
                        if (meta.job.status ?? "") == "failed" || (meta.job.status ?? "") == "canceled" {
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
        YouTubeURLPolicy.normalizedCandidate(raw)
    }

    func isYouTubeHost(_ rawHost: String) -> Bool {
        YouTubeURLPolicy.isYouTubeHost(rawHost)
    }

    func isValidYouTubeVideoId(_ rawValue: String) -> Bool {
        YouTubeURLPolicy.isValidVideoId(rawValue)
    }

    func releaseSecurityScopedAccess(for fileId: String) {
        guard let url = securityScopedURLs.removeValue(forKey: fileId) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    func makeBookmarkData(for url: URL) -> Data? {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #endif
        return try? url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        return try? URL(
            resolvingBookmarkData: data,
            options: options,
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

// MARK: - IngestionViewModel+PanelData

extension IngestionViewModel {
    static let panelCategoryLabels: [String: String] = [
        "documents": "Documents",
        "images": "Images",
        "audio": "Audio",
        "video": "Video",
        "spreadsheets": "Spreadsheets",
        "reports": "Reports",
        "presentations": "Presentations",
        "other": "Other"
    ]

    static let panelCategoryOrder: [String] = [
        "documents", "images", "audio", "video", "spreadsheets", "reports", "presentations", "other"
    ]

    func panelCategoryIconName(_ category: String) -> String {
        switch category {
        case "documents":
            return "doc.text"
        case "images":
            return "photo"
        case "audio":
            return "waveform"
        case "video":
            return "video"
        case "spreadsheets":
            return "tablecells"
        case "reports":
            return "chart.line.text.clipboard"
        case "presentations":
            return "rectangle.on.rectangle.angled"
        default:
            return "folder"
        }
    }

    func updatePanelDerivedState() {
        let needle = panelSearchQuery.trimmed.lowercased()
        let baseItems = items.filter { $0.statusValue != "failed" }
        let filtered = needle.isEmpty ? baseItems : baseItems.filter { item in
            item.file.filenameOriginal.lowercased().contains(needle)
        }
        let searchResults = filtered.sorted(by: Self.sortByCreatedDateDescending)
        let pinnedItems = filtered
            .filter { panelIsReady($0) && ($0.file.pinned ?? false) }
            .sorted(by: Self.sortPinnedItems)
        let unpinned = filtered.filter { !($0.file.pinned ?? false) }
        let grouped = unpinned.reduce(into: [String: [IngestionListItem]]()) { result, item in
            let category = panelCategory(for: item)
            result[category, default: []].append(item)
        }
        let categorized = grouped.mapValues { items in
            items.sorted(by: Self.sortByCreatedDateDescending)
        }
        let categoriesWithItems = Self.panelCategoryOrder.filter {
            categorized[$0]?.isEmpty == false
        }

        let navigationIds: [String]
        if needle.isEmpty {
            var ids = pinnedItems.filter { !panelIsFolder($0) }.map { $0.file.id }
            for category in Self.panelCategoryOrder where categorized[category] != nil {
                ids.append(
                    contentsOf: categorized[category, default: []]
                        .filter { !panelIsFolder($0) }
                        .map { $0.file.id }
                )
            }
            navigationIds = ids
        } else {
            navigationIds = searchResults.filter { !panelIsFolder($0) }.map { $0.file.id }
        }

        panelFilteredItems = filtered
        panelSearchResults = searchResults
        panelPinnedItems = pinnedItems
        panelCategorizedItems = categorized
        panelCategoriesWithItems = categoriesWithItems
        panelNavigationFileIds = navigationIds
    }

    private static func sortByCreatedDateDescending(_ lhs: IngestionListItem, _ rhs: IngestionListItem) -> Bool {
        let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
        let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
        return leftDate > rightDate
    }

    private static func sortPinnedItems(_ lhs: IngestionListItem, _ rhs: IngestionListItem) -> Bool {
        let leftOrder = lhs.file.pinnedOrder ?? Int.max
        let rightOrder = rhs.file.pinnedOrder ?? Int.max
        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        return sortByCreatedDateDescending(lhs, rhs)
    }

    private func panelIsReady(_ item: IngestionListItem) -> Bool {
        (item.job.status ?? "") == "ready" && item.recommendedViewer != nil
    }

    private func panelIsFolder(_ item: IngestionListItem) -> Bool {
        item.file.category == "folder"
    }

    private func panelCategory(for item: IngestionListItem) -> String {
        if let category = item.file.category, !category.isEmpty {
            return category
        }
        let normalized = item.file.mimeOriginal.split(separator: ";").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? item.file.mimeOriginal
        if normalized == "video/youtube" || normalized.hasPrefix("video/") {
            return "video"
        }
        if normalized.hasPrefix("image/") {
            return "images"
        }
        if normalized.hasPrefix("audio/") {
            return "audio"
        }
        if normalized == "application/pdf"
            || normalized == "text/plain"
            || normalized == "text/markdown"
            || normalized == "text/html"
            || normalized == "application/msword"
            || normalized == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" {
            return "documents"
        }
        if normalized == "application/vnd.ms-excel"
            || normalized == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            || normalized == "text/csv" {
            return "spreadsheets"
        }
        if normalized == "application/vnd.ms-powerpoint"
            || normalized == "application/vnd.openxmlformats-officedocument.presentationml.presentation" {
            return "presentations"
        }
        return "other"
    }
}
