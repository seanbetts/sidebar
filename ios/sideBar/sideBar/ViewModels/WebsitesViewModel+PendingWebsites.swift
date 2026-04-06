import Foundation
import sideBarShared

extension WebsitesViewModel {
    /// Source of pending website rows rendered for optimistic sidebar updates.
    public enum PendingWebsiteSource: String {
        case directSave
        case queuedShare
    }

    /// User-facing processing state shown for queued website rows.
    public enum PendingWebsiteStatus: String {
        case queued
        case reading
        case retrying
        case failed

        public var label: String {
            switch self {
            case .queued:
                return "Queued"
            case .reading:
                return "Reading..."
            case .retrying:
                return "Retrying"
            case .failed:
                return "Failed"
            }
        }
    }

    /// Holds a pending website captured from extension and in-app save flows.
    public struct PendingWebsiteItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let domain: String
        public let url: String
        public let canonicalURL: String
        public let source: PendingWebsiteSource
        public let queueItemId: UUID?
        public let jobId: String?
        public let status: PendingWebsiteStatus
        public let selectionFallbackId: String?

        public init(
            id: String,
            title: String,
            domain: String,
            url: String,
            canonicalURL: String,
            source: PendingWebsiteSource,
            queueItemId: UUID? = nil,
            jobId: String? = nil,
            status: PendingWebsiteStatus = .reading,
            selectionFallbackId: String? = nil
        ) {
            self.id = id
            self.title = title
            self.domain = domain
            self.url = url
            self.canonicalURL = canonicalURL
            self.source = source
            self.queueItemId = queueItemId
            self.jobId = jobId
            self.status = status
            self.selectionFallbackId = selectionFallbackId
        }

        /// User-facing status label with YouTube-specific wording for active processing.
        public var statusLabel: String {
            if status == .queued, source == .queuedShare {
                return "Saved for later"
            }
            if status == .reading, YouTubeURLPolicy.extractVideoId(from: url) != nil {
                return "Watching..."
            }
            return status.label
        }

        public var progressMessage: String {
            let isYouTube = YouTubeURLPolicy.extractVideoId(from: url) != nil
            switch status {
            case .queued:
                return isYouTube ? "Queued to watch..." : "Queued to read..."
            case .reading:
                return isYouTube ? "Watching..." : "Reading..."
            case .retrying:
                return "Retrying website save..."
            case .failed:
                return "Website save failed"
            }
        }

        public var canCancel: Bool {
            status != .failed && (jobId != nil || queueItemId != nil)
        }
    }
}

@MainActor
extension WebsitesViewModel {
    private struct QueuedPendingWebsite {
        let canonical: String
        let item: PendingShareItem
        let url: URL
    }

    @discardableResult
    func upsertPendingWebsite(
        from url: URL,
        source: PendingWebsiteSource,
        id: String? = nil,
        queueItemId: UUID? = nil,
        status: PendingWebsiteStatus? = nil,
        selectionFallbackId: String? = nil
    ) -> PendingWebsiteItem {
        let canonical = canonicalWebsiteURLForPendingMatch(url.absoluteString) ?? url.absoluteString
        let resolvedStatus = status ?? defaultPendingWebsiteStatus(for: source)
        if let index = pendingWebsites.firstIndex(where: { $0.canonicalURL == canonical }) {
            let existing = pendingWebsites[index]
            let updated = PendingWebsiteItem(
                id: existing.id,
                title: existing.title,
                domain: existing.domain,
                url: existing.url,
                canonicalURL: existing.canonicalURL,
                source: source,
                queueItemId: queueItemId ?? existing.queueItemId,
                jobId: existing.jobId,
                status: resolvedStatus,
                selectionFallbackId: selectionFallbackId ?? existing.selectionFallbackId
            )
            if updated != existing {
                pendingWebsites[index] = updated
            }
            return pendingWebsites[index]
        }
        let pending = makePendingWebsite(
            from: url,
            source: source,
            id: id,
            queueItemId: queueItemId,
            status: resolvedStatus,
            selectionFallbackId: selectionFallbackId
        )
        pendingWebsites.append(pending)
        return pending
    }

    func removePendingWebsite(for rawURL: String) {
        let key = canonicalWebsiteURLForPendingMatch(rawURL) ?? rawURL
        pendingWebsites.removeAll { $0.canonicalURL == key }
    }

    func removePendingWebsite(id: String) {
        pendingWebsites.removeAll { $0.id == id }
    }

    func removePendingWebsite(queueItemId: UUID) {
        let removedIds = Set(
            pendingWebsites
                .filter { $0.queueItemId == queueItemId }
                .map(\.id)
        )
        pendingWebsites.removeAll { $0.queueItemId == queueItemId }
        if let selectedWebsiteId, removedIds.contains(selectedWebsiteId) {
            self.selectedWebsiteId = nil
        }
    }

    func hasPendingWebsite(for url: URL) -> Bool {
        let key = canonicalWebsiteURLForPendingMatch(url.absoluteString) ?? url.absoluteString
        return pendingWebsites.contains { $0.canonicalURL == key }
    }

    func updatePendingWebsiteJobId(_ jobId: String, for url: URL) {
        let key = canonicalWebsiteURLForPendingMatch(url.absoluteString) ?? url.absoluteString
        guard let index = pendingWebsites.firstIndex(where: { $0.canonicalURL == key }) else { return }
        let existing = pendingWebsites[index]
        pendingWebsites[index] = PendingWebsiteItem(
            id: existing.id,
            title: existing.title,
            domain: existing.domain,
            url: existing.url,
            canonicalURL: existing.canonicalURL,
            source: existing.source,
            queueItemId: existing.queueItemId,
            jobId: jobId,
            status: existing.status,
            selectionFallbackId: existing.selectionFallbackId
        )
    }

    func pendingWebsiteByJobId(_ jobId: String) -> PendingWebsiteItem? {
        pendingWebsites.first { $0.jobId == jobId }
    }

    func pendingWebsite(id: String) -> PendingWebsiteItem? {
        pendingWebsites.first { $0.id == id }
    }

    func updatePendingWebsiteStatus(for rawURL: String, status: PendingWebsiteStatus) {
        let key = canonicalWebsiteURLForPendingMatch(rawURL) ?? rawURL
        guard let index = pendingWebsites.firstIndex(where: { $0.canonicalURL == key }) else { return }
        let existing = pendingWebsites[index]
        pendingWebsites[index] = PendingWebsiteItem(
            id: existing.id,
            title: existing.title,
            domain: existing.domain,
            url: existing.url,
            canonicalURL: existing.canonicalURL,
            source: existing.source,
            queueItemId: existing.queueItemId,
            jobId: existing.jobId,
            status: status,
            selectionFallbackId: existing.selectionFallbackId
        )
    }

    func syncQueuedPendingWebsites(
        with queuedItems: [PendingShareItem],
        readingQueueItemId: UUID? = nil
    ) {
        var orderedQueuedEntries: [QueuedPendingWebsite] = []
        var seenCanonical = Set<String>()
        for item in queuedItems {
            guard item.kind == .website,
                  let raw = item.url,
                  let normalized = WebsiteURLValidator.normalizedCandidate(raw) else {
                continue
            }
            let canonical = canonicalWebsiteURLForPendingMatch(normalized.absoluteString) ?? normalized.absoluteString
            guard seenCanonical.insert(canonical).inserted else { continue }
            orderedQueuedEntries.append(
                QueuedPendingWebsite(canonical: canonical, item: item, url: normalized)
            )
        }
        let queuedCanonical = Set(orderedQueuedEntries.map { $0.canonical })
        let savedCanonical = Set(items.map { canonicalWebsiteURLForPendingMatch($0.url) ?? $0.url })

        pendingWebsites.removeAll {
            guard $0.source == .queuedShare else { return false }
            if savedCanonical.contains($0.canonicalURL) {
                return true
            }
            if queuedCanonical.contains($0.canonicalURL) {
                return false
            }
            // Once a queued share has been handed off to the async save pipeline,
            // keep rendering its pending row until completion or failure removes it.
            return $0.jobId == nil
        }

        for entry in orderedQueuedEntries {
            guard !savedCanonical.contains(entry.canonical) else { continue }
            let status = pendingWebsiteStatus(
                for: entry.item,
                readingQueueItemId: readingQueueItemId
            )

            if let index = pendingWebsites.firstIndex(where: {
                $0.canonicalURL == entry.canonical && $0.source == .queuedShare
            }) {
                pendingWebsites[index] = makePendingWebsite(
                    from: entry.url,
                    source: .queuedShare,
                    id: pendingWebsites[index].id,
                    queueItemId: entry.item.id,
                    status: status
                )
                continue
            }

            guard pendingWebsites.contains(where: { $0.canonicalURL == entry.canonical }) == false else {
                continue
            }
            _ = upsertPendingWebsite(
                from: entry.url,
                source: .queuedShare,
                queueItemId: entry.item.id,
                status: status
            )
        }
    }

    func makePendingWebsite(
        from url: URL,
        source: PendingWebsiteSource,
        id: String? = nil,
        queueItemId: UUID? = nil,
        status: PendingWebsiteStatus? = nil,
        selectionFallbackId: String? = nil
    ) -> PendingWebsiteItem {
        let host = url.host ?? url.absoluteString
        let domain = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        let pendingTitle = YouTubeURLPolicy.extractVideoId(from: url.absoluteString) == nil
            ? "Reading..."
            : "Watching..."
        return PendingWebsiteItem(
            id: id ?? "pending-\(UUID().uuidString)",
            title: pendingTitle,
            domain: domain,
            url: url.absoluteString,
            canonicalURL: canonicalWebsiteURLForPendingMatch(url.absoluteString) ?? url.absoluteString,
            source: source,
            queueItemId: queueItemId,
            status: status ?? defaultPendingWebsiteStatus(for: source),
            selectionFallbackId: selectionFallbackId
        )
    }
    private func defaultPendingWebsiteStatus(for source: PendingWebsiteSource) -> PendingWebsiteStatus {
        switch source {
        case .directSave:
            return .queued
        case .queuedShare:
            return .queued
        }
    }

    private func pendingWebsiteStatus(
        for item: PendingShareItem,
        readingQueueItemId: UUID?
    ) -> PendingWebsiteStatus {
        if readingQueueItemId == item.id {
            return .reading
        }
        if isPendingWebsiteFailed(item) {
            return .failed
        }
        if max(0, item.retryCount ?? 0) > 0 {
            return .retrying
        }
        return .queued
    }
}
