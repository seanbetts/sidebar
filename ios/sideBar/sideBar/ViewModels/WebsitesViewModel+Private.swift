import Foundation
import OSLog
import sideBarShared

@MainActor
extension WebsitesViewModel {
    func normalizedWebsiteURL(from rawURL: String) -> URL? {
        guard let trimmed = rawURL.trimmedOrNil,
              let normalized = WebsiteURLValidator.normalizedCandidate(trimmed) else {
            saveErrorMessage = "Enter a valid URL."
            return nil
        }
        return normalized
    }

    func enqueueOfflineWebsiteSave(for normalizedURL: URL) -> Bool {
        if PendingShareStore.shared.enqueueWebsite(url: normalizedURL.absoluteString) != nil {
            pendingWebsite = makePendingWebsite(from: normalizedURL)
            saveErrorMessage = nil
            toastCenter.show(message: "Saved for later", style: .success)
            return true
        }
        saveErrorMessage = "Could not save for later."
        return false
    }

    func beginWebsiteSave(for normalizedURL: URL) -> String? {
        let previousSelectedId = selectedWebsiteId
        let pending = makePendingWebsite(from: normalizedURL)
        pendingWebsite = pending
        selectedWebsiteId = pending.id
        saveErrorMessage = nil
        isSavingWebsite = true
        isLoadingDetail = true
        return previousSelectedId
    }

    func endWebsiteSave() {
        isSavingWebsite = false
        isLoadingDetail = false
    }

    func validatedSaveData(from response: WebsiteSaveResponse, previousSelectedId: String?) -> WebsiteSaveData? {
        guard response.success, let data = response.data else {
            failWebsiteSave(previousSelectedId: previousSelectedId, message: "Failed to save website")
            return nil
        }
        return data
    }

    func applySavedWebsite(_ data: WebsiteSaveData) async throws {
        selectedWebsiteId = data.id
        try await store.loadDetail(id: data.id, force: true)
        let detail = active
        store.insertItemAtTop(
            WebsiteItem(
                id: data.id,
                title: detail?.title ?? data.title,
                url: detail?.url ?? data.url,
                domain: detail?.domain ?? data.domain,
                savedAt: detail?.savedAt,
                publishedAt: detail?.publishedAt,
                pinned: detail?.pinned ?? false,
                pinnedOrder: detail?.pinnedOrder,
                archived: detail?.archived ?? false,
                faviconUrl: detail?.faviconUrl,
                faviconR2Key: detail?.faviconR2Key,
                youtubeTranscripts: detail?.youtubeTranscripts,
                readingTime: detail?.readingTime,
                updatedAt: detail?.updatedAt,
                lastOpenedAt: detail?.lastOpenedAt,
                deletedAt: nil
            ),
            persist: true
        )
        pendingWebsite = nil
        store.invalidateList()
        Task { [weak self] in
            do {
                try await self?.store.loadList(force: true)
            } catch {
                self?.logger.error("Failed to refresh websites list after save: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func applySavedWebsiteWithoutSelection(_ data: WebsiteSaveData) {
        store.insertItemAtTop(
            WebsiteItem(
                id: data.id,
                title: data.title,
                url: data.url,
                domain: data.domain,
                savedAt: nil,
                publishedAt: nil,
                pinned: false,
                pinnedOrder: nil,
                archived: false,
                faviconUrl: nil,
                faviconR2Key: nil,
                youtubeTranscripts: nil,
                readingTime: nil,
                updatedAt: nil,
                lastOpenedAt: nil,
                deletedAt: nil
            ),
            persist: true
        )
        pendingWebsite = nil
        store.invalidateList()
    }

    func failWebsiteSave(previousSelectedId: String?, message: String) {
        pendingWebsite = nil
        selectedWebsiteId = previousSelectedId
        saveErrorMessage = message
    }

    func updatePanelDerivedState() {
        let needle = panelSearchQuery.trimmed.lowercased()
        let filteredItems: [WebsiteItem]
        if needle.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                item.title.lowercased().contains(needle)
                    || item.domain.lowercased().contains(needle)
                    || item.url.lowercased().contains(needle)
            }
        }

        let pinnedItemsSorted = items
            .filter { $0.pinned && !$0.archived }
            .sorted(by: Self.sortPinnedItems)
        let mainItems = items.filter { !$0.pinned && !$0.archived }
        let archivedItems = items.filter { $0.archived }

        panelFilteredItems = filteredItems
        panelPinnedItemsSorted = pinnedItemsSorted
        panelMainItems = mainItems
        panelArchivedItems = archivedItems
        if needle.isEmpty {
            panelNavigationWebsiteIds = pinnedItemsSorted.map { $0.id } + mainItems.map { $0.id }
        } else {
            panelNavigationWebsiteIds = filteredItems.map { $0.id }
        }
    }

    private static func sortPinnedItems(_ lhs: WebsiteItem, _ rhs: WebsiteItem) -> Bool {
        let leftOrder = lhs.pinnedOrder ?? Int.max
        let rightOrder = rhs.pinnedOrder ?? Int.max
        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        let leftDate = DateParsing.parseISO8601(lhs.updatedAt) ?? .distantPast
        let rightDate = DateParsing.parseISO8601(rhs.updatedAt) ?? .distantPast
        return leftDate > rightDate
    }

    func isDeleteConflict(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else { return false }
        switch apiError {
        case .apiError(let message):
            return message.localizedCaseInsensitiveContains("updated since last sync")
        case .requestFailed(409):
            return true
        default:
            return false
        }
    }

    func retryDeleteAfterRefresh(id: String, fallbackUpdatedAt: String?) async -> Bool {
        do {
            try await store.loadList(force: true)
        } catch {
            return false
        }
        if items.contains(where: { $0.id == id }) == false {
            if selectedWebsiteId == id {
                clearSelection()
            }
            return true
        }
        let refreshedUpdatedAt = store.currentUpdatedAt(id: id) ?? fallbackUpdatedAt
        do {
            try await api.delete(id: id, clientUpdatedAt: refreshedUpdatedAt)
            store.removeItem(id: id, persist: true)
            if selectedWebsiteId == id {
                clearSelection()
            }
            return true
        } catch {
            return false
        }
    }

    func makePendingWebsite(from url: URL) -> PendingWebsiteItem {
        let host = url.host ?? url.absoluteString
        let domain = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        let pendingTitle = YouTubeURLPolicy.extractVideoId(from: url.absoluteString) == nil
            ? "Reading..."
            : "Watching..."
        return PendingWebsiteItem(
            id: "pending-\(UUID().uuidString)",
            title: pendingTitle,
            domain: domain,
            url: url.absoluteString
        )
    }

    func clearPendingIfNeeded(items: [WebsiteItem]) {
        guard let pendingWebsite else { return }
        let pendingUrl = pendingWebsite.url
        if items.contains(where: { $0.url == pendingUrl }) {
            self.pendingWebsite = nil
        }
    }

    func setTranscriptRequestInFlight(
        _ isInFlight: Bool,
        websiteId: String,
        videoId: String
    ) {
        var next = inFlightTranscriptRequests
        var videoIds = next[websiteId] ?? Set<String>()
        if isInFlight {
            videoIds.insert(videoId)
        } else {
            videoIds.remove(videoId)
        }
        if videoIds.isEmpty {
            next.removeValue(forKey: websiteId)
        } else {
            next[websiteId] = videoIds
        }
        inFlightTranscriptRequests = next
    }

    func syncTranscriptPolling(for active: WebsiteDetail?) {
        guard let active else {
            stopTranscriptPolling()
            return
        }
        var activeKeys = Set<String>()
        for (videoId, entry) in active.youtubeTranscripts ?? [:] {
            guard Self.isTranscriptStatusPending(entry.status) else { continue }
            activeKeys.insert(Self.transcriptPollingKey(websiteId: active.id, videoId: videoId))
            startTranscriptPollingIfNeeded(websiteId: active.id, videoId: videoId)
        }
        for key in Array(transcriptPollingTasks.keys) where !activeKeys.contains(key) {
            stopTranscriptPolling(key: key)
        }
    }

    func startTranscriptPollingIfNeeded(websiteId: String, videoId: String) {
        let key = Self.transcriptPollingKey(websiteId: websiteId, videoId: videoId)
        guard transcriptPollingTasks[key] == nil else { return }
        transcriptPollingTasks[key] = Task { [weak self] in
            var consecutiveFailures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await Task.sleep(
                        nanoseconds: self.transcriptPollingDelayNanoseconds(
                            key: key,
                            consecutiveFailures: consecutiveFailures
                        )
                    )
                } catch {
                    return
                }
                switch await self.pollTranscriptStatus(
                    websiteId: websiteId,
                    videoId: videoId,
                    key: key
                ) {
                case .completed:
                    return
                case .pending:
                    consecutiveFailures = 0
                case .retryableFailure:
                    consecutiveFailures += 1
                    guard consecutiveFailures >= self.transcriptPollMaxConsecutiveFailures else {
                        continue
                    }
                    self.markTranscriptPollingFailed(websiteId: websiteId, videoId: videoId, key: key)
                    return
                }
            }
        }
    }

    private func pollTranscriptStatus(
        websiteId: String,
        videoId: String,
        key: String
    ) async -> TranscriptPollingResult {
        guard selectedWebsiteId == websiteId else {
            stopTranscriptPolling(key: key)
            return .completed
        }
        guard networkStatus.isOffline == false else {
            return .retryableFailure
        }
        do {
            try await store.loadDetail(id: websiteId, force: true)
        } catch {
            return .retryableFailure
        }
        guard let current = active, current.id == websiteId else {
            return .retryableFailure
        }
        guard let status = current.youtubeTranscripts?[videoId]?.status?.lowercased() else {
            stopTranscriptPolling(key: key)
            return .completed
        }
        guard Self.isTranscriptStatusPending(status) == false else {
            return .pending
        }
        if status == "failed" || status == "canceled" {
            errorMessage = current.youtubeTranscripts?[videoId]?.error ?? "Transcript failed."
        }
        stopTranscriptPolling(key: key)
        return .completed
    }

    func markTranscriptPollingFailed(websiteId: String, videoId: String, key: String) {
        let message = "Could not refresh transcript status. Retry transcription."
        let currentFileId = active?.youtubeTranscripts?[videoId]?.fileId
        store.applyTranscriptQueuedUpdate(
            websiteId: websiteId,
            videoId: videoId,
            status: "failed",
            fileId: currentFileId,
            error: message
        )
        errorMessage = message
        stopTranscriptPolling(key: key)
    }

    func stopTranscriptPolling(
        websiteId: String? = nil,
        videoId: String? = nil,
        key: String? = nil
    ) {
        if let key {
            transcriptPollingTasks[key]?.cancel()
            transcriptPollingTasks[key] = nil
            return
        }
        if let websiteId, let videoId {
            let entryKey = Self.transcriptPollingKey(websiteId: websiteId, videoId: videoId)
            transcriptPollingTasks[entryKey]?.cancel()
            transcriptPollingTasks[entryKey] = nil
            return
        }
        for task in transcriptPollingTasks.values {
            task.cancel()
        }
        transcriptPollingTasks = [:]
    }

    private enum TranscriptPollingResult {
        case completed
        case pending
        case retryableFailure
    }

    private func transcriptPollingDelayNanoseconds(
        key: String,
        consecutiveFailures: Int
    ) -> UInt64 {
        let exponent = min(max(consecutiveFailures, 0), 4)
        let base = Double(transcriptPollIntervalNanoseconds)
        let maxValue = Double(transcriptPollMaxIntervalNanoseconds)
        let scaled = min(base * pow(2, Double(exponent)), maxValue)
        let jitter = Double(
            deterministicJitter(
                seed: "transcript:\(key)",
                attempt: consecutiveFailures,
                maxValue: transcriptPollJitterWindowNanoseconds
            )
        )
        return UInt64(scaled + jitter)
    }

    private func deterministicJitter(seed: String, attempt: Int, maxValue: UInt64) -> UInt64 {
        guard maxValue > 0 else { return 0 }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(seed):\(attempt)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return UInt64(Double(hash % 1_000) / 1_000 * Double(maxValue))
    }

    static func transcriptPollingKey(websiteId: String, videoId: String) -> String {
        "\(websiteId):\(videoId)"
    }

    static func isTranscriptStatusPending(_ status: String?) -> Bool {
        guard let status else { return false }
        switch status.lowercased() {
        case "queued", "processing", "retrying":
            return true
        default:
            return false
        }
    }

    static func pendingTranscriptMap(from items: [IngestionListItem]) -> [String: Set<String>] {
        let pendingStatuses = Set(["queued", "processing", "retrying"])
        var map: [String: Set<String>] = [:]
        for item in items {
            guard let status = item.job.status?.lowercased(),
                  pendingStatuses.contains(status),
                  let metadata = item.file.sourceMetadata,
                  metadataBool(metadata, key: "website_transcript") == true,
                  let websiteId = metadataString(metadata, key: "website_id"),
                  let videoId = metadataString(metadata, key: "video_id") else {
                continue
            }
            map[websiteId, default: []].insert(videoId)
        }
        return map
    }

    static func metadataString(_ metadata: [String: AnyCodable], key: String) -> String? {
        guard let value = metadata[key]?.value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func metadataBool(_ metadata: [String: AnyCodable], key: String) -> Bool? {
        guard let value = metadata[key]?.value else { return nil }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    /// Refreshes widget data by fetching the latest websites list
    /// Called by background refresh task to keep widgets up-to-date
    func refreshWidgetData() async {
        do {
            try await store.loadList(force: true)
        } catch {
            // Silently fail - widget will use cached data
        }
    }
}
