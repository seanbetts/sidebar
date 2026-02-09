import Foundation
import sideBarShared
#if canImport(WidgetKit)
import WidgetKit
#endif

extension WebsitesStore {
    // MARK: - Background Refresh

    func refreshList() async {
        guard canAttemptBackgroundRefresh() else {
            return
        }
        guard !isRefreshingList else {
            return
        }
        isRefreshingList = true
        defer { isRefreshingList = false }
        do {
            let response = try await api.list()
            updateArchivedSummary(from: response, persist: true)
            applyListUpdate(response.items, persist: true)
            markBackgroundRefreshSuccess()
        } catch {
            markBackgroundRefreshFailure()
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    func refreshArchivedList(force: Bool = false) async {
        if !force {
            guard canAttemptBackgroundRefresh() else {
                return
            }
        }
        if isRefreshingArchived {
            await waitForArchivedRefresh()
            return
        }
        guard shouldRefreshArchivedList(force: force) else {
            return
        }
        isRefreshingArchived = true
        defer { isRefreshingArchived = false }
        do {
            let response = try await api.listArchived(limit: archivedListLimit, offset: 0)
            applyArchivedUpdate(response.items, persist: true)
            archivedListSyncedAt = archivedSummary?.lastUpdated
            persistArchivedSyncToken()
            markBackgroundRefreshSuccess()
            Task { [weak self] in
                await self?.prefetchArchivedDetails(from: response.items)
            }
        } catch {
            markBackgroundRefreshFailure()
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    func waitForArchivedRefresh() async {
        var elapsed: UInt64 = 0
        while isRefreshingArchived, elapsed < archivedRefreshWaitTimeoutNanoseconds {
            try? await Task.sleep(nanoseconds: archivedRefreshPollIntervalNanoseconds)
            elapsed += archivedRefreshPollIntervalNanoseconds
        }
    }

    func refreshDetail(id: String) async {
        guard canAttemptBackgroundRefresh() else {
            return
        }
        do {
            let response = try await api.get(id: id)
            applyDetailUpdate(response, persist: true)
            markBackgroundRefreshSuccess()
        } catch {
            markBackgroundRefreshFailure()
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    // MARK: - List Management

    func applyListUpdate(_ incoming: [WebsiteItem], persist: Bool) {
        let currentActive = items.filter { !$0.archived }
        guard shouldUpdateList(incoming, current: currentActive) else {
            return
        }
        let archivedItems = items.filter { $0.archived }
        items = mergeItems(active: incoming, archived: archivedItems)
        if persist {
            persistListCache()
            indexWebsitesInSpotlight(incoming)
        }
        updateWidgetData(from: incoming)
    }

    func applyArchivedUpdate(_ incoming: [WebsiteItem], persist: Bool) {
        let currentArchived = items.filter { $0.archived }
        guard shouldUpdateList(incoming, current: currentArchived) else {
            return
        }
        let activeItems = items.filter { !$0.archived }
        items = mergeItems(active: activeItems, archived: incoming)
        if persist {
            persistListCache()
        }
    }

    func shouldUpdateList(_ incoming: [WebsiteItem], current: [WebsiteItem]) -> Bool {
        guard current.count == incoming.count else {
            return true
        }
        let existing = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for item in incoming {
            guard let current = existing[item.id] else {
                return true
            }
            if current.updatedAt != item.updatedAt
                || current.pinned != item.pinned
                || current.pinnedOrder != item.pinnedOrder
                || current.archived != item.archived
                || current.lastOpenedAt != item.lastOpenedAt
                || current.title != item.title
                || current.deletedAt != item.deletedAt
                || current.faviconUrl != item.faviconUrl
                || current.faviconR2Key != item.faviconR2Key
                || current.readingTime != item.readingTime {
                return true
            }
        }
        return false
    }

    func mergeItems(active: [WebsiteItem], archived: [WebsiteItem]) -> [WebsiteItem] {
        var merged = active
        let activeIds = Set(active.map(\.id))
        for item in archived where !activeIds.contains(item.id) {
            merged.append(item)
        }
        return merged
    }

    // MARK: - Detail Management

    func applyDetailUpdate(_ incoming: WebsiteDetail, persist: Bool) {
        guard shouldUpdateDetail(incoming) else {
            return
        }
        active = incoming
        if persist {
            if shouldPersistDetail(incoming) {
                persistDetail(incoming)
            } else {
                clearPersistedDetail(id: incoming.id)
            }
        }
    }

    func shouldUpdateDetail(_ incoming: WebsiteDetail) -> Bool {
        guard let current = active else {
            return true
        }
        return current.updatedAt != incoming.updatedAt
            || current.content != incoming.content
            || current.youtubeTranscripts != incoming.youtubeTranscripts
    }

    func shouldPersistDetail(_ detail: WebsiteDetail) -> Bool {
        guard detail.archived else {
            return true
        }
        return ArchivedRetentionPolicy.contains(
            date: DateParsing.parseISO8601(detail.updatedAt),
            retentionDays: archivedDetailRetentionDays
        )
    }

    func updateDetail(_ detail: WebsiteDetail, with item: WebsiteItem) -> WebsiteDetail {
        WebsiteDetail(
            id: detail.id,
            title: item.title,
            url: item.url,
            urlFull: detail.urlFull,
            domain: item.domain,
            content: detail.content,
            source: detail.source,
            savedAt: item.savedAt ?? detail.savedAt,
            publishedAt: item.publishedAt ?? detail.publishedAt,
            pinned: item.pinned,
            pinnedOrder: item.pinnedOrder,
            archived: item.archived,
            faviconUrl: item.faviconUrl ?? detail.faviconUrl,
            faviconR2Key: item.faviconR2Key ?? detail.faviconR2Key,
            youtubeTranscripts: detail.youtubeTranscripts ?? item.youtubeTranscripts,
            readingTime: item.readingTime ?? detail.readingTime,
            updatedAt: item.updatedAt ?? detail.updatedAt,
            lastOpenedAt: item.lastOpenedAt ?? detail.lastOpenedAt
        )
    }

    // MARK: - Offline Detail

    func offlineDetailError(for id: String) -> Error {
        let message: String
        if let item = itemForDetail(id: id) {
            if item.archived {
                if isWithinArchivedRetention(updatedAt: item.updatedAt) {
                    message = "This archived website hasn't been cached yet. Go online to load it."
                } else {
                    message = "Archived content isn't available offline."
                }
            } else {
                message = "This website isn't available offline."
            }
        } else {
            message = "This website isn't available offline."
        }
        return WebsiteDetailOfflineError(message: message)
    }

    func itemForDetail(id: String) -> WebsiteItem? {
        if let item = items.first(where: { $0.id == id }) {
            return item
        }
        if let active, active.id == id {
            return WebsiteItem(
                id: active.id,
                title: active.title,
                url: active.url,
                domain: active.domain,
                savedAt: active.savedAt,
                publishedAt: active.publishedAt,
                pinned: active.pinned,
                pinnedOrder: active.pinnedOrder,
                archived: active.archived,
                faviconUrl: active.faviconUrl,
                faviconR2Key: active.faviconR2Key,
                youtubeTranscripts: active.youtubeTranscripts,
                readingTime: active.readingTime,
                updatedAt: active.updatedAt,
                lastOpenedAt: active.lastOpenedAt,
                deletedAt: nil
            )
        }
        return nil
    }

    func isWithinArchivedRetention(updatedAt: String?) -> Bool {
        ArchivedRetentionPolicy.contains(
            date: DateParsing.parseISO8601(updatedAt),
            retentionDays: archivedDetailRetentionDays
        )
    }

    func hasCachedDetail(id: String) -> Bool {
        let cacheKey = CacheKeys.websiteDetail(id: id)
        let cached: WebsiteDetail? = cache.get(key: cacheKey)
        if cached != nil {
            return true
        }
        if let offlineStore, offlineStore.get(key: cacheKey, as: WebsiteDetail.self) != nil {
            return true
        }
        return false
    }

    func prefetchArchivedDetails(from items: [WebsiteItem]) async {
        guard archivedDetailPrefetchLimit > 0 else { return }
        guard !(networkStatus?.isOffline ?? false) else { return }
        let candidates = items.filter {
            $0.archived && isWithinArchivedRetention(updatedAt: $0.updatedAt)
        }
        let pending = candidates.filter { !hasCachedDetail(id: $0.id) }
        guard !pending.isEmpty else { return }
        for item in pending.prefix(archivedDetailPrefetchLimit) {
            do {
                let detail = try await api.get(id: item.id)
                if shouldPersistDetail(detail) {
                    persistDetail(detail)
                } else {
                    clearPersistedDetail(id: detail.id)
                }
            } catch {
                continue
            }
        }
    }

    // MARK: - Archived Summary

    func updateArchivedSummary(from response: WebsitesResponse, persist: Bool) {
        let summary = ArchivedSummary(
            count: response.archivedCount,
            lastUpdated: response.archivedLastUpdated
        )
        guard !summary.isEmpty else {
            return
        }
        archivedSummary = summary
        if persist, summary.count == 0 {
            removeArchivedItems()
            archivedListSyncedAt = summary.lastUpdated
            persistArchivedSyncToken()
        }
    }

    func shouldRefreshArchivedList(force: Bool) -> Bool {
        if force {
            return true
        }
        loadArchivedSyncTokenIfNeeded()
        if let summary = archivedSummary {
            if summary.count == 0 {
                return false
            }
            let hasArchivedItems = items.contains { $0.archived }
            guard let serverUpdated = summary.lastUpdated else {
                return !hasArchivedItems
            }
            if let archivedListSyncedAt {
                return archivedListSyncedAt != serverUpdated
            }
            return true
        }
        return true
    }

    func loadArchivedSyncTokenIfNeeded() {
        guard !archivedSyncLoaded else {
            return
        }
        archivedSyncLoaded = true
        archivedListSyncedAt = offlineStore?.get(
            key: CacheKeys.websitesArchivedSync,
            as: String.self
        )
    }

    func persistArchivedSyncToken() {
        guard let archivedListSyncedAt else {
            return
        }
        let lastSyncAt = Date()
        offlineStore?.set(
            key: CacheKeys.websitesArchivedSync,
            entityType: "websitesArchivedSync",
            value: archivedListSyncedAt,
            lastSyncAt: lastSyncAt
        )
    }

    func removeArchivedItems() {
        items = items.filter { !$0.archived }
        if active?.archived == true {
            active = nil
        }
        persistListCache()
    }

    // MARK: - Persistence

    func persistDetail(_ detail: WebsiteDetail) {
        cache.set(key: CacheKeys.websiteDetail(id: detail.id), value: detail, ttlSeconds: CachePolicy.websiteDetail)
        let lastSyncAt = Date()
        offlineStore?.set(
            key: CacheKeys.websiteDetail(id: detail.id),
            entityType: "website",
            value: detail,
            lastSyncAt: lastSyncAt
        )
    }

    func clearPersistedDetail(id: String) {
        cache.remove(key: CacheKeys.websiteDetail(id: id))
        offlineStore?.remove(key: CacheKeys.websiteDetail(id: id))
    }

    func persistListCache() {
        let response = WebsitesResponse(
            items: items,
            archivedCount: archivedSummary?.count,
            archivedLastUpdated: archivedSummary?.lastUpdated
        )
        cache.set(key: CacheKeys.websitesList, value: response, ttlSeconds: CachePolicy.websitesList)
        let lastSyncAt = Date()
        offlineStore?.set(
            key: CacheKeys.websitesList,
            entityType: "websitesList",
            value: response,
            lastSyncAt: lastSyncAt
        )
    }

    // MARK: - Spotlight

    func indexWebsitesInSpotlight(_ items: [WebsiteItem]) {
        guard let indexer = spotlightIndexer else { return }
        let websites = items
            .filter { !$0.archived && $0.deletedAt == nil }
            .map { item in
                SpotlightWebsite(
                    id: item.id,
                    title: item.title,
                    url: item.url,
                    domain: item.domain,
                    savedAt: DateParsing.parseISO8601(item.savedAt)
                )
            }
        Task {
            await indexer.indexWebsites(websites)
        }
    }

    func removeWebsiteFromSpotlight(id: String) {
        guard let indexer = spotlightIndexer else { return }
        Task {
            await indexer.removeWebsite(id: id)
        }
    }

    // MARK: - Widget Data

    func updateWidgetData(from items: [WebsiteItem]) {
        let savedSites = items
            .filter { !$0.pinned && !$0.archived }
            .sorted { ($0.savedAt ?? "") > ($1.savedAt ?? "") }
            .map { WidgetWebsite(from: $0) }
        let displaySites = Array(savedSites.prefix(10))
        let data = WidgetWebsiteData(websites: displaySites, totalCount: savedSites.count)
        WidgetDataManager.shared.store(data, for: .websites)
    }
}

struct WebsiteDetailOfflineError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
