// swiftlint:disable file_length
import Foundation
import OSLog
import sideBarShared

private struct WebsitePanelDerivedState {
    let filteredItems: [WebsiteItem]
    let pinnedItemsSorted: [WebsiteItem]
    let mainItems: [WebsiteItem]
    let archivedItems: [WebsiteItem]
    let navigationIds: [String]
}

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

    func enqueueOfflineWebsiteSave(
        for normalizedURL: URL,
        selectAfterSave: Bool
    ) -> Bool {
        if let queuedItem = PendingShareStore.shared.enqueueWebsite(url: normalizedURL.absoluteString) {
            let previousSelectedId = selectedWebsiteId
            let pending = upsertPendingWebsite(
                from: normalizedURL,
                source: selectAfterSave ? .directSave : .queuedShare,
                queueItemId: queuedItem.id,
                status: .queued,
                selectionFallbackId: selectAfterSave ? previousSelectedId : nil
            )
            if selectAfterSave {
                selectedWebsiteId = pending.id
                store.clearActive()
            }
            saveErrorMessage = nil
            toastCenter.show(message: "Saved for later", style: .success)
            return true
        }
        saveErrorMessage = "Could not save for later."
        return false
    }

    func beginWebsiteSave(for normalizedURL: URL) -> String? {
        let previousSelectedId = selectedWebsiteId
        let pending = upsertPendingWebsite(
            from: normalizedURL,
            source: .directSave,
            status: .queued,
            selectionFallbackId: previousSelectedId
        )
        selectedWebsiteId = pending.id
        store.clearActive()
        saveErrorMessage = nil
        isSavingWebsite = true
        isLoadingDetail = true
        return previousSelectedId
    }

    func endWebsiteSave() {
        isSavingWebsite = false
        isLoadingDetail = false
    }

    func applySavedWebsite(
        _ website: WebsiteDetail,
        pendingURL: URL,
        shouldSelectOnCompletion: Bool
    ) {
        if shouldSelectOnCompletion {
            selectedWebsiteId = website.id
            store.applyDetailUpdate(website, persist: true)
        } else if store.shouldPersistDetail(website) {
            store.persistDetail(website)
        } else {
            store.clearPersistedDetail(id: website.id)
        }
        store.insertItemAtTop(
            WebsiteItem(detail: website),
            persist: true
        )
        removePendingWebsite(for: pendingURL.absoluteString)
        store.invalidateList()
        Task { [weak self] in
            do {
                try await self?.store.loadList(force: true)
            } catch {
                self?.logger.error("Failed to refresh websites list after save: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func recoverSavedWebsiteWithoutSelection(pendingURL: URL) async -> Bool {
        do {
            try await store.loadList(force: true)
        } catch {
            return false
        }

        let target = canonicalWebsiteURLForPendingMatch(pendingURL.absoluteString) ?? pendingURL.absoluteString
        guard items.contains(where: {
            (canonicalWebsiteURLForPendingMatch($0.url) ?? $0.url) == target
        }) else {
            return false
        }

        removePendingWebsite(for: pendingURL.absoluteString)
        saveErrorMessage = nil
        return true
    }

    func failWebsiteSave(previousSelectedId: String?, pendingURL: URL, message: String) {
        updatePendingWebsiteStatus(for: pendingURL.absoluteString, status: .failed)
        selectedWebsiteId = previousSelectedId
        saveErrorMessage = message
    }

    func retryPendingWebsite(id: String) async -> Bool {
        guard let pending = pendingWebsite(id: id),
              pending.source == .directSave,
              let normalized = normalizedWebsiteURL(from: pending.url) else {
            return false
        }

        let previousSelectedId = selectedWebsiteId
        selectedWebsiteId = pending.id
        saveErrorMessage = nil
        isSavingWebsite = true
        isLoadingDetail = true
        updatePendingWebsiteStatus(for: normalized.absoluteString, status: .retrying)

        if let jobId = pending.jobId {
            jobPollingTasks[jobId]?.cancel()
            clearWebsiteJobPolling(jobId: jobId)
            jobProgressCoordinator.cancel(jobId: jobId)
        }

        do {
            let response = try await api.save(url: normalized.absoluteString)
            updatePendingWebsiteJobId(response.jobId, for: normalized)
            registerWebsiteSaveJob(
                jobId: response.jobId,
                pendingURL: normalized
            )
            return true
        } catch {
            endWebsiteSave()
            failWebsiteSave(
                previousSelectedId: previousSelectedId,
                pendingURL: normalized,
                message: ErrorMapping.message(for: error)
            )
            return false
        }
    }

    func updatePanelDerivedState() {
        let searchActive = !panelSearchQuery.trimmed.isEmpty
        let derivedState = WebsiteQueueDebugTrace.measure(
            "websites-panel.derived-state",
            details: [
                "items_count=\(items.count)",
                "pending_count=\(pendingWebsites.count)",
                "search_active=\(searchActive)"
            ]
        ) { () -> WebsitePanelDerivedState in
            let needle = SearchTextMatcher.normalizedQuery(panelSearchQuery)
            let filteredItems: [WebsiteItem]
            if needle.isEmpty {
                filteredItems = items
            } else {
                filteredItems = items.filter { item in
                    SearchTextMatcher.contains(
                        normalizedQuery: needle,
                        in: [item.title, item.domain, item.url]
                    )
                }
            }

            let pinnedItemsSorted = items
                .filter { $0.pinned && !$0.archived }
                .sorted(by: Self.sortPinnedItems)
            let mainItems = items.filter { !$0.pinned && !$0.archived }
            let archivedItems = items.filter { $0.archived }
            let navigationIds: [String]
            if needle.isEmpty {
                navigationIds = pinnedItemsSorted.map { $0.id } + mainItems.map { $0.id }
            } else {
                navigationIds = filteredItems.map { $0.id }
            }

            return WebsitePanelDerivedState(
                filteredItems: filteredItems,
                pinnedItemsSorted: pinnedItemsSorted,
                mainItems: mainItems,
                archivedItems: archivedItems,
                navigationIds: navigationIds
            )
        }

        panelFilteredItems = derivedState.filteredItems
        panelPinnedItemsSorted = derivedState.pinnedItemsSorted
        panelMainItems = derivedState.mainItems
        panelArchivedItems = derivedState.archivedItems
        panelNavigationWebsiteIds = derivedState.navigationIds

        WebsiteQueueDebugTrace.log(
            "websites-panel.derived-state.result",
            details: [
                "filtered_count=\(derivedState.filteredItems.count)",
                "pinned_count=\(derivedState.pinnedItemsSorted.count)",
                "main_count=\(derivedState.mainItems.count)",
                "archived_count=\(derivedState.archivedItems.count)",
                "navigation_count=\(derivedState.navigationIds.count)"
            ]
        )
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
        case .appError(let appError):
            return appError.diagnostics["statusCode"] == "409"
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

    func canonicalWebsiteURLForPendingMatch(_ raw: String) -> String? {
        guard let trimmed = raw.trimmedOrNil else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        if YouTubeURLPolicy.isYouTubeHost(host),
           let videoId = YouTubeURLPolicy.extractVideoId(from: candidate) {
            return "https://www.youtube.com/watch?v=\(videoId)"
        }

        components.query = nil
        components.fragment = nil
        return components.string
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

    func syncTranscriptProgress(for active: WebsiteDetail?) {
        guard let active else {
            stopTranscriptPolling()
            return
        }
        for (videoId, entry) in active.youtubeTranscripts ?? [:] {
            guard Self.isTranscriptStatusPending(entry.status),
                  let fileId = entry.fileId else {
                continue
            }
            recordPendingTranscriptJob(websiteId: active.id, videoId: videoId)
            registerTranscriptJob(websiteId: active.id, jobId: fileId)
        }
    }

    func syncTranscriptPolling(for active: WebsiteDetail?) {
        syncTranscriptProgress(for: active)
    }

    func registerWebsiteSaveJob(jobId: String, pendingURL: URL) {
        jobProgressCoordinator.register(
            AsyncJobDescriptor(
                domain: .websiteSave,
                entityId: pendingURL.absoluteString,
                jobId: jobId,
                terminalStatuses: ["completed", "failed", "canceled", "stalled"]
            )
        )
    }

    func registerTranscriptJob(websiteId: String, jobId: String) {
        jobProgressCoordinator.register(
            AsyncJobDescriptor(
                domain: .websiteTranscript,
                entityId: websiteId,
                jobId: jobId,
                terminalStatuses: ["ready", "completed", "failed", "canceled", "stalled"]
            )
        )
    }

    func recordPendingTranscriptJob(websiteId: String, videoId: String) {
        let normalizedVideoId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVideoId.isEmpty else { return }
        pendingTranscriptJobs[websiteId, default: []].insert(normalizedVideoId)
    }

    func clearPendingTranscriptJob(websiteId: String, videoId: String) {
        let normalizedVideoId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVideoId.isEmpty else { return }
        pendingTranscriptJobs[websiteId]?.remove(normalizedVideoId)
        if pendingTranscriptJobs[websiteId]?.isEmpty == true {
            pendingTranscriptJobs.removeValue(forKey: websiteId)
        }
    }

    func scheduleWebsiteJobTerminalRefresh(
        entityId: String?,
        requiresDetailRefresh: Bool
    ) async {
        await onJobTerminalState(
            WebsitesRefreshAdapter.jobTerminalChange(
                entityId: entityId,
                requiresDetailRefresh: requiresDetailRefresh
            )
        )
    }

    func applyWebsiteSaveRealtimeCompletion(from item: WebsiteItem) async {
        guard let pending = pendingWebsiteMatching(realtimeItem: item),
              let jobId = pending.jobId,
              jobProgressCoordinator.hasActiveJob(jobId: jobId) else {
            return
        }
        guard case .terminal = await jobProgressCoordinator.applyRealtimeStatus(
            jobId: jobId,
            status: AsyncJobStatus(rawValue: "completed"),
            userMessage: nil
        ) else {
            return
        }

        let shouldSelectDetail = selectedWebsiteId == pending.id && pending.source == .directSave
        clearWebsiteJobPolling(jobId: jobId)
        removePendingWebsite(id: pending.id)
        saveErrorMessage = nil
        if pending.source == .directSave {
            endWebsiteSave()
        }
        if shouldSelectDetail {
            selectedWebsiteId = item.id
        }
        await scheduleWebsiteJobTerminalRefresh(
            entityId: item.id,
            requiresDetailRefresh: shouldSelectDetail
        )
    }

    func applyTranscriptRealtimeProgress(from item: WebsiteItem) async {
        var shouldScheduleTerminalRefresh = false
        for (videoId, entry) in item.youtubeTranscripts ?? [:] {
            guard let status = entry.status?.lowercased(),
                  Self.isTranscriptStatusPending(status) == false,
                  let fileId = entry.fileId,
                  jobProgressCoordinator.hasActiveJob(jobId: fileId) else {
                continue
            }
            let result = await jobProgressCoordinator.applyRealtimeStatus(
                jobId: fileId,
                status: AsyncJobStatus(rawValue: status),
                userMessage: entry.error
            )
            guard case .terminal = result else { continue }
            clearPendingTranscriptJob(websiteId: item.id, videoId: videoId)
            if status == "failed" || status == "canceled" {
                errorMessage = entry.error ?? "Transcript failed."
                showTranscriptFailureToast()
            }
            shouldScheduleTerminalRefresh = true
        }
        if shouldScheduleTerminalRefresh {
            await scheduleWebsiteJobTerminalRefresh(
                entityId: item.id,
                requiresDetailRefresh: selectedWebsiteId == item.id
            )
        }
    }

    func startTranscriptPollingIfNeeded(websiteId: String, videoId: String) {
        let key = Self.transcriptPollingKey(websiteId: websiteId, videoId: videoId)
        guard allowsFallbackPolling(.websites, true) else {
            stopTranscriptPolling(key: key)
            return
        }
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
        guard allowsFallbackPolling(.websites, true) else {
            stopTranscriptPolling(key: key)
            return .completed
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
        let fileId = current.youtubeTranscripts?[videoId]?.fileId
        if let fileId,
           jobProgressCoordinator.hasActiveJob(jobId: fileId) {
            _ = await jobProgressCoordinator.applyRealtimeStatus(
                jobId: fileId,
                status: AsyncJobStatus(rawValue: status),
                userMessage: current.youtubeTranscripts?[videoId]?.error
            )
        }
        clearPendingTranscriptJob(websiteId: websiteId, videoId: videoId)
        await scheduleWebsiteJobTerminalRefresh(
            entityId: websiteId,
            requiresDetailRefresh: selectedWebsiteId == websiteId
        )
        if status == "failed" || status == "canceled" {
            errorMessage = current.youtubeTranscripts?[videoId]?.error ?? "Transcript failed."
            showTranscriptFailureToast()
        }
        stopTranscriptPolling(key: key)
        return .completed
    }

    func markTranscriptPollingFailed(websiteId: String, videoId: String, key: String) {
        let message = "Could not refresh transcript status. Retry transcription."
        clearPendingTranscriptJob(websiteId: websiteId, videoId: videoId)
        errorMessage = message
        showTranscriptFailureToast()
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

    private func pendingWebsiteMatching(realtimeItem item: WebsiteItem) -> PendingWebsiteItem? {
        let canonical = canonicalWebsiteURLForPendingMatch(item.url) ?? item.url
        return pendingWebsites.first {
            $0.canonicalURL == canonical && $0.jobId != nil
        }
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
