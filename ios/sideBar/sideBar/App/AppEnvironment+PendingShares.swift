import Foundation
import sideBarShared

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
    maxRetryCount: Int = 5
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
    private static let websiteQueueMaxRetryCount = 5

    public func consumePendingShares() async {
        guard authState == .active else { return }
        guard !isConsumingPendingShares else { return }
        isConsumingPendingShares = true
        defer { isConsumingPendingShares = false }

        let pending = PendingShareStore.shared.loadAll()
        websitesViewModel.syncPendingWebsitesFromQueuedShares(pending)
        guard !pending.isEmpty else { return }
        guard !connectivityMonitor.isOffline else { return }

        let processingResult = await processPendingShares(pending)
        let retainedItems = processingResult.items
        let droppedQueuedWebsiteCount = processingResult.droppedQueuedWebsiteCount

        PendingShareStore.shared.replaceAll(retainedItems)
        if droppedQueuedWebsiteCount > 0 {
            let message = droppedQueuedWebsiteCount == 1
                ? "Removed a queued website after repeated save failures."
                : "Removed \(droppedQueuedWebsiteCount) queued websites after repeated save failures."
            toastCenter.show(message: message)
        }

        websitesViewModel.syncPendingWebsitesFromQueuedShares(retainedItems)
    }

    private func processPendingShares(
        _ pending: [PendingShareItem]
    ) async -> (items: [PendingShareItem], droppedQueuedWebsiteCount: Int) {
        let now = Date()
        var retainedItems: [PendingShareItem] = []
        var droppedQueuedWebsiteCount = 0

        for item in pending {
            let outcome = await processPendingShare(item, now: now)
            if let retainedItem = outcome.item {
                retainedItems.append(retainedItem)
            }
            droppedQueuedWebsiteCount += outcome.droppedQueuedWebsiteCount
        }

        return (retainedItems, droppedQueuedWebsiteCount)
    }

    private func processPendingShare(
        _ item: PendingShareItem,
        now: Date
    ) async -> (item: PendingShareItem?, droppedQueuedWebsiteCount: Int) {
        if item.kind == .website {
            return await processPendingWebsite(item, now: now)
        }
        let shouldKeep = await shouldKeepPendingShare(item)
        return shouldKeep ? (item, 0) : (nil, 0)
    }

    private func processPendingWebsite(
        _ item: PendingShareItem,
        now: Date
    ) async -> (item: PendingShareItem?, droppedQueuedWebsiteCount: Int) {
        guard isPendingWebsiteReadyForRetry(item, now: now) else {
            return (item, 0)
        }
        guard let url = item.url else {
            return (nil, 1)
        }
        websitesViewModel.saveErrorMessage = nil
        let saved = await websitesViewModel.saveWebsite(
            url: url,
            selectAfterSave: false
        )
        guard !saved else {
            return (nil, 0)
        }
        let retryItem = nextPendingWebsiteRetryItem(
            from: item,
            now: now,
            errorMessage: websitesViewModel.saveErrorMessage,
            maxRetryCount: Self.websiteQueueMaxRetryCount
        )
        return retryItem.map { ($0, 0) } ?? (nil, 1)
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
            resolveFileURL: { item in
                PendingShareStore.shared.resolveFileURL(for: item)
            },
            startUpload: { [weak self] fileURL in
                guard let self else { return false }
                self.ingestionViewModel.startUpload(url: fileURL)
                return true
            }
        )
    }
}
