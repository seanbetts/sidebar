import Foundation
import sideBarShared

let pendingWebsiteQueueMaxRetryCount = 5

@MainActor
final class PendingShareReplayStartSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    var started: Bool {
        hasStarted
    }

    func wait() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func markStarted() {
        guard !hasStarted else { return }
        hasStarted = true
        continuation?.resume()
        continuation = nil
    }
}

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
        selectAfterSave: item.selectAfterSave,
        filePath: item.filePath,
        filename: item.filename,
        mimeType: item.mimeType,
        retryCount: nextAttempt,
        nextRetryAt: nextRetryAt,
        lastError: errorMessage,
        websiteJobId: item.websiteJobId
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
        selectAfterSave: item.selectAfterSave,
        filePath: item.filePath,
        filename: item.filename,
        mimeType: item.mimeType,
        retryCount: max(max(0, item.retryCount ?? 0), maxRetryCount),
        nextRetryAt: nil,
        lastError: errorMessage,
        websiteJobId: item.websiteJobId
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
    prepareFileForUpload: @escaping (PendingShareItem) -> URL?,
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
        guard let fileURL = prepareFileForUpload(item) else {
            return true
        }
        let started = startUpload(fileURL)
        return !started
    @unknown default:
        return true
    }
}
