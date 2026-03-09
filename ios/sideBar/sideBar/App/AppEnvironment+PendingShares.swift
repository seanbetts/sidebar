import Foundation
import sideBarShared

let pendingWebsiteQueueMaxRetryCount = 5

enum PendingWebsiteFailureKind {
    case retryable
    case terminal
}

func pendingWebsiteFailureKind(for message: String?) -> PendingWebsiteFailureKind {
    guard let message else { return .retryable }
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .retryable }
    let lowered = trimmed.lowercased()

    let terminalSignals = [
        "enter a valid url",
        "invalid url",
        "invalid request url",
        "unsupported url",
        "unsupported content",
        "url required",
        "missing url"
    ]
    if terminalSignals.contains(where: lowered.contains) {
        return .terminal
    }

    if let status = extractHTTPStatusCode(from: lowered) {
        if [400, 404, 410, 422].contains(status) {
            return .terminal
        }
        return .retryable
    }

    return .retryable
}

func extractHTTPStatusCode(from loweredMessage: String) -> Int? {
    guard let markerRange = loweredMessage.range(of: "http ") else {
        return nil
    }
    let suffix = loweredMessage[markerRange.upperBound...]
    let digits = suffix.prefix(while: { $0.isNumber })
    guard digits.count == 3 else {
        return nil
    }
    return Int(digits)
}

func pendingWebsiteRetryDelay(
    attempt: Int,
    baseDelay: TimeInterval = 30,
    maxDelay: TimeInterval = 30 * 60
) -> TimeInterval {
    let safeAttempt = max(1, attempt)
    let scaled = baseDelay * pow(2, Double(safeAttempt - 1))
    return min(maxDelay, scaled)
}

func isPendingWebsiteReadyForRetry(_ item: PendingShareItem, now: Date = Date()) -> Bool {
    guard item.kind == .website else { return true }
    guard let nextRetryAt = item.nextRetryAt else { return true }
    return nextRetryAt <= now
}

func nextPendingWebsiteRetryItem(
    from item: PendingShareItem,
    now: Date,
    errorMessage: String?,
    maxRetryCount: Int = pendingWebsiteQueueMaxRetryCount
) -> PendingShareItem? {
    let nextAttempt = max(0, item.retryCount ?? 0) + 1
    if nextAttempt >= maxRetryCount {
        return nil
    }
    if pendingWebsiteFailureKind(for: errorMessage) == .terminal {
        return nil
    }
    let nextRetryAt = now.addingTimeInterval(
        pendingWebsiteRetryDelay(attempt: nextAttempt)
    )
    return PendingShareItem(
        id: item.id,
        kind: item.kind,
        createdAt: item.createdAt,
        url: item.url,
        filePath: item.filePath,
        filename: item.filename,
        mimeType: item.mimeType,
        retryCount: nextAttempt,
        nextRetryAt: nextRetryAt,
        lastError: errorMessage
    )
}

func failedPendingWebsiteItem(
    from item: PendingShareItem,
    errorMessage: String?,
    maxRetryCount: Int = pendingWebsiteQueueMaxRetryCount
) -> PendingShareItem {
    PendingShareItem(
        id: item.id,
        kind: item.kind,
        createdAt: item.createdAt,
        url: item.url,
        filePath: item.filePath,
        filename: item.filename,
        mimeType: item.mimeType,
        retryCount: max(max(0, item.retryCount ?? 0), maxRetryCount),
        nextRetryAt: nil,
        lastError: errorMessage
    )
}

func isPendingWebsiteFailed(
    _ item: PendingShareItem,
    maxRetryCount: Int = pendingWebsiteQueueMaxRetryCount
) -> Bool {
    guard item.kind == .website else { return false }
    guard item.nextRetryAt == nil else { return false }
    return max(0, item.retryCount ?? 0) >= maxRetryCount
}

func shouldKeepPendingShareItem(
    _ item: PendingShareItem,
    isOffline: @escaping () -> Bool,
    saveWebsite: @escaping (String) async -> Bool,
    ingestYouTube: @escaping (String) async -> String?,
    resolveFileURL: @escaping (PendingShareItem) -> URL?,
    startUpload: @escaping (URL) -> Bool
) async -> Bool {
    switch item.kind {
    case .website:
        guard let url = item.url else { return false }
        let success = await saveWebsite(url)
        return !success
    case .youtube:
        guard !isOffline() else { return true }
        guard let url = item.url else { return true }
        let error = await ingestYouTube(url)
        return error != nil
    case .file, .image:
        guard !isOffline() else { return true }
        guard let fileURL = resolveFileURL(item) else {
            return true
        }
        let started = startUpload(fileURL)
        return !started
    @unknown default:
        return true
    }
}

extension AppEnvironment {
    public func enqueueWebsiteSave(
        url: String,
        selectAfterSave: Bool = true
    ) async -> Bool {
        guard let normalized = WebsiteURLValidator.normalizedCandidate(url) else {
            websitesViewModel.saveErrorMessage = "Enter a valid URL."
            return false
        }
        guard let queuedItem = storage.pendingShareStore.enqueueWebsite(
            url: normalized.absoluteString
        ) else {
            websitesViewModel.saveErrorMessage = "Could not save for later."
            return false
        }
        websitesViewModel.saveErrorMessage = nil

        let resetQueueItem = PendingShareItem(
            id: queuedItem.id,
            kind: queuedItem.kind,
            createdAt: queuedItem.createdAt,
            url: queuedItem.url,
            filePath: queuedItem.filePath,
            filename: queuedItem.filename,
            mimeType: queuedItem.mimeType,
            retryCount: nil,
            nextRetryAt: nil,
            lastError: nil
        )
        var items = storage.pendingShareStore.loadAll()
        if let index = items.firstIndex(where: { $0.id == queuedItem.id }) {
            items[index] = resetQueueItem
            storage.pendingShareStore.replaceAll(items)
        }
        websitesViewModel.syncPendingWebsitesFromQueuedShares(
            storage.pendingShareStore.loadAll(),
            readingQueueItemId: queuedItem.id
        )

        guard !connectivityMonitor.isOffline else {
            if selectAfterSave {
                toastCenter.show(message: "Saved for later", style: .success)
            }
            return true
        }
        return await processQueuedWebsiteNow(
            queueItemId: queuedItem.id,
            selectAfterSave: selectAfterSave
        )
    }

    public func consumePendingShares() async {
        guard authState == .active else { return }
        guard !isConsumingPendingShares else { return }
        isConsumingPendingShares = true
        defer { isConsumingPendingShares = false }

        let pending = storage.pendingShareStore.loadAll()
        websitesViewModel.syncPendingWebsitesFromQueuedShares(pending)
        guard !pending.isEmpty else { return }
        guard !connectivityMonitor.isOffline else { return }

        let retainedItems = await processPendingShares(pending)
        storage.pendingShareStore.replaceAll(retainedItems)
        websitesViewModel.syncPendingWebsitesFromQueuedShares(retainedItems)
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
        websitesViewModel.syncPendingWebsitesFromQueuedShares(storage.pendingShareStore.loadAll())
    }

    private func processPendingShares(_ pending: [PendingShareItem]) async -> [PendingShareItem] {
        let now = Date()
        var retainedItems: [PendingShareItem] = []

        for (index, item) in pending.enumerated() {
            if item.kind == .website {
                let remaining = Array(pending[index...])
                websitesViewModel.syncPendingWebsitesFromQueuedShares(
                    retainedItems + remaining,
                    readingQueueItemId: item.id
                )
            }
            if let retainedItem = await processPendingShare(item, now: now) {
                retainedItems.append(retainedItem)
            }
        }

        return retainedItems
    }

    private func processPendingShare(
        _ item: PendingShareItem,
        now: Date
    ) async -> PendingShareItem? {
        if item.kind == .website {
            return await processPendingWebsite(item, now: now)
        }
        let shouldKeep = await shouldKeepPendingShare(item)
        return shouldKeep ? item : nil
    }

    private func processQueuedWebsiteNow(
        queueItemId: UUID,
        selectAfterSave: Bool
    ) async -> Bool {
        let now = Date()
        let items = storage.pendingShareStore.loadAll()
        guard let item = items.first(where: { $0.id == queueItemId }) else {
            return true
        }
        let processed = await processPendingWebsite(
            item,
            now: now,
            selectAfterSave: selectAfterSave,
            forceAttempt: true
        )
        let updatedItems = items.compactMap { current -> PendingShareItem? in
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
        forceAttempt: Bool = false
    ) async -> PendingShareItem? {
        if isPendingWebsiteFailed(item) && !forceAttempt {
            return item
        }
        guard forceAttempt || isPendingWebsiteReadyForRetry(item, now: now) else {
            return item
        }
        guard let url = item.url else {
            return nil
        }
        websitesViewModel.saveErrorMessage = nil
        let saved = await websitesViewModel.saveWebsite(
            url: url,
            selectAfterSave: selectAfterSave
        )
        guard !saved else {
            return nil
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
            resolveFileURL: { [self] item in
                self.storage.pendingShareStore.resolveFileURL(for: item)
            },
            startUpload: { [weak self] fileURL in
                guard let self else { return false }
                self.ingestionViewModel.startUpload(url: fileURL)
                return true
            }
        )
    }
}
