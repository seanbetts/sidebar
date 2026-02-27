import Foundation

@MainActor
extension WebsitesViewModel {
    @discardableResult
    func upsertPendingWebsite(
        from url: URL,
        source: PendingWebsiteSource,
        id: String? = nil
    ) -> PendingWebsiteItem {
        let canonical = canonicalWebsiteURLForPendingMatch(url.absoluteString) ?? url.absoluteString
        if let index = pendingWebsites.firstIndex(where: { $0.canonicalURL == canonical }) {
            let existing = pendingWebsites[index]
            if existing.source != source {
                let updated = PendingWebsiteItem(
                    id: existing.id,
                    title: existing.title,
                    domain: existing.domain,
                    url: existing.url,
                    canonicalURL: existing.canonicalURL,
                    source: source
                )
                pendingWebsites[index] = updated
                return updated
            }
            return existing
        }
        let pending = makePendingWebsite(from: url, source: source, id: id)
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

    func syncQueuedPendingWebsites(with urls: [URL]) {
        let canonicalToURL: [String: URL] = urls.reduce(into: [:]) { partialResult, url in
            let canonical = canonicalWebsiteURLForPendingMatch(url.absoluteString) ?? url.absoluteString
            partialResult[canonical] = url
        }
        let queuedCanonical = Set(canonicalToURL.keys)

        pendingWebsites.removeAll {
            $0.source == .queuedShare && !queuedCanonical.contains($0.canonicalURL)
        }
        for canonical in queuedCanonical {
            guard pendingWebsites.contains(where: { $0.canonicalURL == canonical }) == false,
                  let url = canonicalToURL[canonical] else {
                continue
            }
            _ = upsertPendingWebsite(from: url, source: .queuedShare)
        }
    }

    func makePendingWebsite(
        from url: URL,
        source: PendingWebsiteSource,
        id: String? = nil
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
            source: source
        )
    }

    func clearPendingIfNeeded(items: [WebsiteItem]) {
        guard !pendingWebsites.isEmpty else { return }
        let savedKeys = Set(items.map { canonicalWebsiteURLForPendingMatch($0.url) ?? $0.url })
        pendingWebsites.removeAll { savedKeys.contains($0.canonicalURL) }
    }
}
