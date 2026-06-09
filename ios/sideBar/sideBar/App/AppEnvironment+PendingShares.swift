// swiftlint:disable file_length
import Foundation
import sideBarShared

extension AppEnvironment {
    nonisolated static func shouldReconcileQueuedWebsitesOnItemsChange(authState: AuthState) -> Bool {
        authState == .active
    }

    var hasPendingWebsiteCoordinatorWork: Bool {
        hasPendingWebsiteBackgroundWork || storage.extensionEventStore.hasQueuedWebsiteEvents()
    }

    var hasPendingWebsiteBackgroundWork: Bool {
        let hasQueuedWebsiteShares = storage.pendingShareStore.loadAll().contains { $0.kind == .website }
        let hasInFlightWebsiteJobs = websitesViewModel.pendingWebsites.contains { $0.jobId != nil }
        return hasQueuedWebsiteShares || hasInFlightWebsiteJobs
    }

    func performBackgroundWebsiteContinuation(maxDuration: TimeInterval = 20) async -> Bool {
        guard authState == .active,
              isProtectedContentReady,
              connectivityMonitor.offlineCapabilityPolicy.canAttemptServerWrite else {
            return false
        }

        await consumePendingShares()
        guard allowsFallbackPolling(section: .websites, hasActiveJob: true) else {
            return false
        }
        let completed = await websitesViewModel.continuePendingWebsiteJobsInBackground(
            maxDuration: maxDuration
        )
        pruneCompletedPersistedWebsiteJobs()
        return completed
    }

    func performBackgroundWriteQueueFlush() async -> Bool {
        guard authState == .active,
              connectivityMonitor.offlineCapabilityPolicy.canAttemptServerWrite else {
            return false
        }

        await writeQueue.processQueue()
        return !(await writeQueue.hasPendingWritesNeedingFlush())
    }

    func reconcileQueuedWebsitesWithSavedItems(
        trigger: String = "direct",
        savedItemCount: Int? = nil
    ) {
        guard hasPendingWebsiteCoordinatorWork else { return }
        let existing = storage.pendingShareStore.loadAll()
        let resolvedSavedItemCount = savedItemCount ?? websitesStore.items.count
        let pruned = prunedQueuedWebsiteItems(
            existing,
            context: trigger,
            savedItemCount: resolvedSavedItemCount
        )
        WebsiteQueueDebugTrace.log(
            "queued-websites.reconcile.result",
            details: [
                "trigger=\(trigger)",
                "saved_count=\(resolvedSavedItemCount)",
                "queued_before=\(existing.count)",
                "queued_after=\(pruned.count)",
                "replaced=\(pruned.count != existing.count)"
            ]
        )
        guard pruned.count != existing.count else { return }
        storage.pendingShareStore.replaceAll(pruned)
        websitesViewModel.syncPendingWebsitesFromQueuedShares(pruned)
    }

    func scheduleQueuedWebsiteReconciliation(
        trigger: String = "direct",
        savedItemCount: Int? = nil
    ) {
        guard hasPendingWebsiteCoordinatorWork else { return }
        queuedWebsiteReconcileTrigger = trigger
        queuedWebsiteReconcileSavedItemCount = savedItemCount
        guard queuedWebsiteReconcileTask == nil else { return }
        queuedWebsiteReconcileTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let resolvedTrigger = self.queuedWebsiteReconcileTrigger
            let resolvedSavedItemCount = self.queuedWebsiteReconcileSavedItemCount
            self.queuedWebsiteReconcileTask = nil
            self.queuedWebsiteReconcileSavedItemCount = nil
            self.reconcileQueuedWebsitesWithSavedItems(
                trigger: resolvedTrigger,
                savedItemCount: resolvedSavedItemCount
            )
        }
    }

    public func enqueueWebsiteSave(
        url: String,
        selectAfterSave: Bool = true
    ) async -> Bool {
        guard let normalized = WebsiteURLValidator.normalizedCandidate(url) else {
            websitesViewModel.saveErrorMessage = "Enter a valid URL."
            return false
        }
        return await websitesViewModel.saveWebsite(
            url: normalized.absoluteString,
            selectAfterSave: selectAfterSave
        )
    }

    func consumePendingShares(
        replayStartSignal: PendingShareReplayStartSignal? = nil
    ) async {
        guard authState == .active, isProtectedContentReady else {
            replayStartSignal?.markStarted()
            return
        }
        guard !isConsumingPendingShares else {
            replayStartSignal?.markStarted()
            return
        }
        isConsumingPendingShares = true
        defer { isConsumingPendingShares = false }

        let loadedPending = storage.pendingShareStore.loadAll()
        let initialPending = prunedQueuedWebsiteItems(
            loadedPending,
            context: "consumePendingShares.initial"
        )
        if initialPending.count != loadedPending.count {
            storage.pendingShareStore.replaceAll(initialPending)
        }

        guard connectivityMonitor.offlineCapabilityPolicy.canAttemptServerWrite else {
            websitesViewModel.syncPendingWebsitesFromQueuedShares(initialPending)
            replayStartSignal?.markStarted()
            return
        }

        let pending = initialPending
        websitesViewModel.syncPendingWebsitesFromQueuedShares(pending)
        guard !pending.isEmpty else {
            replayStartSignal?.markStarted()
            return
        }

        let processingState = PendingShareProcessingState()
        let retainedItems: [PendingShareItem]
        do {
            retainedItems = try await processPendingShares(
                pending,
                replayStartSignal: replayStartSignal,
                state: processingState
            )
        } catch is CancellationError {
            retainedItems = processingState.retainedItems + Array(pending[processingState.nextItemIndex...])
        } catch {
            retainedItems = processingState.retainedItems + Array(pending[processingState.nextItemIndex...])
        }
        let reconciled = reconcilePendingShareResults(
            processedSnapshot: pending,
            retainedItems: retainedItems
        )
        let prunedItems = prunedQueuedWebsiteItems(
            reconciled.items,
            context: "consumePendingShares.final"
        )
        if storage.pendingShareStore.replaceAllCleaningRemovedStagedFiles(prunedItems) {
            websitesViewModel.syncPendingWebsitesFromQueuedShares(prunedItems)
        } else {
            websitesViewModel.syncPendingWebsitesFromQueuedShares(storage.pendingShareStore.loadAll())
        }
        replayStartSignal?.markStarted()
    }

    public func retryPendingQueuedWebsite(_ queueItemId: UUID) async {
        let items = storage.pendingShareStore.loadAll()
        guard !items.isEmpty else { return }

        var didUpdate = false
        let updatedItems = items.map { item -> PendingShareItem in
            guard item.id == queueItemId, item.kind == .website else {
                return item
            }
            didUpdate = true
            return PendingShareItem(
                id: item.id,
                kind: item.kind,
                createdAt: item.createdAt,
                url: item.url,
                selectAfterSave: item.selectAfterSave,
                filePath: item.filePath,
                filename: item.filename,
                mimeType: item.mimeType,
                retryCount: nil,
                nextRetryAt: nil,
                lastError: nil
            )
        }
        guard didUpdate else { return }

        storage.pendingShareStore.replaceAll(updatedItems)
        websitesViewModel.syncPendingWebsitesFromQueuedShares(updatedItems)
        await consumePendingShares()
    }

    public func removePendingQueuedWebsite(_ queueItemId: UUID) {
        storage.pendingShareStore.remove(ids: [queueItemId])
        websitesViewModel.removePendingWebsite(queueItemId: queueItemId)
        websitesViewModel.syncPendingWebsitesFromQueuedShares(storage.pendingShareStore.loadAll())
    }

    public func cancelPendingWebsite(_ pending: WebsitesViewModel.PendingWebsiteItem) async {
        guard pending.status != .failed, pending.jobId != nil else {
            if let queueItemId = pending.queueItemId {
                removePendingQueuedWebsite(queueItemId)
            } else {
                websitesViewModel.removePendingWebsite(id: pending.id)
            }
            return
        }

        await websitesViewModel.cancelPendingWebsite(id: pending.id)
        guard websitesViewModel.pendingWebsite(id: pending.id) == nil else { return }

        if let queueItemId = pending.queueItemId {
            storage.pendingShareStore.remove(ids: [queueItemId])
        }
        websitesViewModel.syncPendingWebsitesFromQueuedShares(storage.pendingShareStore.loadAll())
    }

    private func processPendingShares(
        _ pending: [PendingShareItem],
        replayStartSignal: PendingShareReplayStartSignal? = nil,
        state: PendingShareProcessingState
    ) async throws -> [PendingShareItem] {
        let now = Date()

        for (index, item) in pending.enumerated() {
            state.nextItemIndex = index
            try Task.checkCancellation()
            if item.kind == .website {
                let remaining = Array(pending[index...])
                websitesViewModel.syncPendingWebsitesFromQueuedShares(
                    state.retainedItems + remaining,
                    readingQueueItemId: item.id
                )
            }
            if let retainedItem = try await processPendingShare(
                item,
                now: now,
                replayStartSignal: replayStartSignal
            ) {
                state.retainedItems.append(retainedItem)
            }
            state.nextItemIndex = index + 1
        }

        return state.retainedItems
    }

    private func processPendingShare(
        _ item: PendingShareItem,
        now: Date,
        replayStartSignal: PendingShareReplayStartSignal? = nil
    ) async throws -> PendingShareItem? {
        if item.kind == .website {
            return try await processPendingWebsite(
                item,
                now: now,
                replayStartSignal: replayStartSignal
            )
        }
        let shouldKeep = await shouldKeepPendingShare(item)
        return shouldKeep ? item : nil
    }

    private func processQueuedWebsiteNow(
        queueItemId: UUID,
        selectAfterSave: Bool
    ) async -> Bool {
        let now = Date()
        let snapshot = storage.pendingShareStore.loadAll()
        guard let item = snapshot.first(where: { $0.id == queueItemId }) else {
            return true
        }
        let processed: PendingShareItem?
        do {
            processed = try await processPendingWebsite(
                item,
                now: now,
                selectAfterSave: selectAfterSave,
                forceAttempt: true
            )
        } catch is CancellationError {
            return false
        } catch {
            return false
        }
        let latestItems = storage.pendingShareStore.loadAll()
        let updatedItems = latestItems.compactMap { current -> PendingShareItem? in
            if current.id == queueItemId {
                return processed
            }
            return current
        }
        storage.pendingShareStore.replaceAll(updatedItems)
        websitesViewModel.syncPendingWebsitesFromQueuedShares(updatedItems)
        return processed == nil
    }

    private func processPendingWebsite(
        _ item: PendingShareItem,
        now: Date,
        selectAfterSave: Bool = false,
        forceAttempt: Bool = false,
        replayStartSignal: PendingShareReplayStartSignal? = nil
    ) async throws -> PendingShareItem? {
        if isPendingWebsiteFailed(item) && !forceAttempt {
            return item
        }
        guard forceAttempt || isPendingWebsiteReadyForRetry(item, now: now) else {
            return item
        }
        guard let url = item.url else {
            return nil
        }
        if let jobId = item.websiteJobId {
            return await continuePersistedWebsiteJob(item, jobId: jobId, url: url)
        }
        websitesViewModel.saveErrorMessage = nil
        replayStartSignal?.markStarted()
        let shouldSelectAfterSave = selectAfterSave || item.selectAfterSave == true
        let saved = try await websitesViewModel.saveQueuedWebsiteStartingJob(
            url: url,
            selectAfterSave: shouldSelectAfterSave
        )
        guard !saved else {
            return acceptedWebsiteJobItem(from: item, url: url)
        }
        let retryItem = nextPendingWebsiteRetryItem(
            from: item,
            now: now,
            errorMessage: websitesViewModel.saveErrorMessage,
            maxRetryCount: pendingWebsiteQueueMaxRetryCount
        )
        return retryItem ?? failedPendingWebsiteItem(
            from: item,
            errorMessage: websitesViewModel.saveErrorMessage,
            maxRetryCount: pendingWebsiteQueueMaxRetryCount
        )
    }

    private func continuePersistedWebsiteJob(
        _ item: PendingShareItem,
        jobId: String,
        url: String
    ) async -> PendingShareItem? {
        guard allowsFallbackPolling(section: .websites, hasActiveJob: true) else {
            return item
        }
        guard let pendingURL = URL(string: url) else {
            return nil
        }
        _ = websitesViewModel.upsertPendingWebsite(
            from: pendingURL,
            source: item.selectAfterSave == true ? .directSave : .queuedShare,
            queueItemId: item.id,
            jobId: jobId,
            status: .reading
        )
        let isTerminal = await websitesViewModel.refreshWebsiteJobStatus(
            jobId: jobId,
            pendingURL: pendingURL,
            previousSelectedId: nil,
            shouldSelectOnCompletion: item.selectAfterSave == true
        )
        return isTerminal ? nil : item
    }

    private func acceptedWebsiteJobItem(from item: PendingShareItem, url: String) -> PendingShareItem? {
        let canonical = websitesViewModel.canonicalWebsiteURLForPendingMatch(url) ?? url
        guard let pending = websitesViewModel.pendingWebsites.first(where: {
            $0.canonicalURL == canonical && $0.jobId != nil
        }) else {
            return nil
        }
        return PendingShareItem(
            id: item.id,
            kind: item.kind,
            createdAt: item.createdAt,
            url: item.url,
            selectAfterSave: item.selectAfterSave,
            filePath: item.filePath,
            filename: item.filename,
            mimeType: item.mimeType,
            retryCount: item.retryCount,
            nextRetryAt: item.nextRetryAt,
            lastError: item.lastError,
            websiteJobId: pending.jobId
        )
    }

    private func pruneCompletedPersistedWebsiteJobs() {
        let activeJobIds = Set(websitesViewModel.pendingWebsites.compactMap(\.jobId))
        let currentItems = storage.pendingShareStore.loadAll()
        let prunedItems = currentItems.filter { item in
            guard item.kind == .website, let websiteJobId = item.websiteJobId else {
                return true
            }
            return activeJobIds.contains(websiteJobId)
        }
        guard prunedItems.count != currentItems.count else { return }
        storage.pendingShareStore.replaceAll(prunedItems)
        websitesViewModel.syncPendingWebsitesFromQueuedShares(prunedItems)
    }

    private func shouldKeepPendingShare(_ item: PendingShareItem) async -> Bool {
        guard item.kind != .website else { return true }
        return await shouldKeepPendingShareItem(
            item,
            isOffline: { [weak self] in
                self?.ingestionViewModel.isOfflineForIngestion() ?? true
            },
            saveWebsite: { _ in
                false
            },
            ingestYouTube: { [weak self] url in
                guard let self else { return "Environment released." }
                return await self.ingestionViewModel.ingestYouTube(
                    url: url,
                    showQueuedToast: false
                )
            },
            prepareFileForUpload: { [self] item in
                self.storage.pendingShareStore.prepareFileForUpload(for: item)
            },
            startUpload: { [weak self] fileURL in
                guard let self else { return false }
                return self.ingestionViewModel.startPendingShareUpload(url: fileURL)
            }
        )
    }

    private func reconcilePendingShareResults(
        processedSnapshot: [PendingShareItem],
        retainedItems: [PendingShareItem]
    ) -> (items: [PendingShareItem], hadConcurrentQueuedItems: Bool) {
        let processedIds = Set(processedSnapshot.map(\.id))
        let latestItems = storage.pendingShareStore.loadAll()
        let latestIds = Set(latestItems.map(\.id))
        let filteredRetainedItems = retainedItems.filter { latestIds.contains($0.id) }
        let retainedIds = Set(filteredRetainedItems.map(\.id))
        let concurrentItems = latestItems.filter { item in
            !processedIds.contains(item.id) && !retainedIds.contains(item.id)
        }
        return (filteredRetainedItems + concurrentItems, !concurrentItems.isEmpty)
    }

    private func prunedQueuedWebsiteItems(
        _ items: [PendingShareItem],
        context: String,
        savedItemCount: Int? = nil
    ) -> [PendingShareItem] {
        let resolvedSavedItemCount = savedItemCount ?? websitesStore.items.count
        var savedKeyCount = 0
        let pruned = WebsiteQueueDebugTrace.measure(
            "queued-websites.prune",
            details: [
                "context=\(context)",
                "saved_count=\(resolvedSavedItemCount)",
                "queued_count=\(items.count)"
            ]
        ) {
            let savedKeys = Set(websitesStore.items.map {
                websitesViewModel.canonicalWebsiteURLForPendingMatch($0.url) ?? $0.url
            })
            savedKeyCount = savedKeys.count
            guard !savedKeys.isEmpty else { return items }
            return items.filter { item in
                guard item.kind == .website, let rawURL = item.url else { return true }
                let candidate = websitesViewModel.canonicalWebsiteURLForPendingMatch(rawURL) ?? rawURL
                return !savedKeys.contains(candidate)
            }
        }
        WebsiteQueueDebugTrace.log(
            "queued-websites.prune.result",
            details: [
                "context=\(context)",
                "saved_count=\(resolvedSavedItemCount)",
                "saved_key_count=\(savedKeyCount)",
                "queued_before=\(items.count)",
                "queued_after=\(pruned.count)",
                "pruned=\(items.count - pruned.count)"
            ]
        )
        return pruned
    }
}

private final class PendingShareProcessingState {
    var retainedItems: [PendingShareItem] = []
    var nextItemIndex = 0
}
