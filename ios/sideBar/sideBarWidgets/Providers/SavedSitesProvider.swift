import SwiftUI
import WidgetKit
import sideBarShared

struct SavedSitesEntry: TimelineEntry {
    let date: Date
    let data: WidgetWebsiteData
    let isAuthenticated: Bool
    let faviconDataByWebsiteId: [String: Data]

    static let placeholder = SavedSitesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true,
        faviconDataByWebsiteId: [:]
    )

    static let notAuthenticated = SavedSitesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false,
        faviconDataByWebsiteId: [:]
    )
}

struct SavedSitesProvider: TimelineProvider {
    typealias Entry = SavedSitesEntry

    private let dataManager: WidgetDataManager
    private let now: () -> Date
    private let refreshData: @Sendable (Date) async throws -> WidgetWebsiteData
    private let faviconFetcher: @Sendable ([WidgetWebsite]) async -> [String: Data]
    private let faviconCacheLoad: ([WidgetWebsite]) -> [String: Data]
    private let faviconCacheStore: ([String: Data]) -> Void

    init(
        dataManager: WidgetDataManager = .shared,
        now: @escaping () -> Date = Date.init,
        refreshData: @escaping @Sendable (Date) async throws -> WidgetWebsiteData = { currentDate in
            let environment = try WidgetAPIEnvironment()
            return try await WebsitesWidgetRefreshClient(environment: environment)
                .refreshSavedWebsites(now: currentDate)
        },
        faviconFetcher: @escaping @Sendable ([WidgetWebsite]) async -> [String: Data] = { websites in
            await Self.fetchFaviconDataByWebsiteId(for: websites)
        },
        faviconCacheLoad: @escaping ([WidgetWebsite]) -> [String: Data] = { websites in
            WidgetFaviconCache.load(for: websites)
        },
        faviconCacheStore: @escaping ([String: Data]) -> Void = { faviconDataByWebsiteId in
            WidgetFaviconCache.store(faviconDataByWebsiteId)
        }
    ) {
        self.dataManager = dataManager
        self.now = now
        self.refreshData = refreshData
        self.faviconFetcher = faviconFetcher
        self.faviconCacheLoad = faviconCacheLoad
        self.faviconCacheStore = faviconCacheStore
    }

    func placeholder(in context: Context) -> SavedSitesEntry {
        Self.previewEntry(for: context.family, now: now())
    }

    func getSnapshot(in context: Context, completion: @escaping (SavedSitesEntry) -> Void) {
        if context.isPreview {
            completion(Self.previewEntry(for: context.family, now: now()))
            return
        }
        Task {
            let entry = await entry(for: now())
            recordProviderDiagnostics(stage: "snapshot", entry: entry)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SavedSitesEntry>) -> Void) {
        Task {
            completion(await timeline(for: now()))
        }
    }

    func timeline(for currentDate: Date) async -> Timeline<SavedSitesEntry> {
        let entry = await entry(for: currentDate)
        recordProviderDiagnostics(stage: "timeline", entry: entry)
        guard entry.isAuthenticated else {
            return Timeline(entries: [entry], policy: .after(nextMidnight(from: currentDate)))
        }
        let nextUpdate = WidgetRefreshPolicy.nextRefreshDate(
            lastUpdated: entry.data.lastUpdated,
            contentType: .websites,
            now: currentDate
        )
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    func entry(for date: Date) async -> SavedSitesEntry {
        let hasCachedSnapshot = dataManager.hasStoredSnapshot(for: .websites)
        let isAuthenticated = dataManager.isAuthenticated()
        let canDisplayContent = WidgetDisplayAuthorization.canDisplayContent(
            isAuthenticated: isAuthenticated,
            hasCachedSnapshot: hasCachedSnapshot
        )
        guard canDisplayContent else {
            return .notAuthenticated
        }

        var data: WidgetWebsiteData = dataManager.load(for: .websites)
        let decision = WidgetRefreshCoordinator.decision(
            contentType: .websites,
            lastUpdated: hasCachedSnapshot ? data.lastUpdated : nil,
            hasCachedSnapshot: hasCachedSnapshot,
            isAuthenticated: isAuthenticated,
            now: date
        )

        if decision.shouldAttemptRefresh {
            do {
                let refreshed = try await refreshData(date)
                dataManager.store(refreshed, for: .websites)
                data = refreshed
            } catch {}
        }

        let candidateSites = Self.candidateSites(for: data.websites)
        var faviconDataByWebsiteId = faviconCacheLoad(candidateSites)
        let uncachedSites = candidateSites.filter { faviconDataByWebsiteId[$0.id] == nil }
        if !uncachedSites.isEmpty {
            let fetched = await faviconFetcher(uncachedSites)
            if !fetched.isEmpty {
                faviconCacheStore(fetched)
                faviconDataByWebsiteId.merge(fetched, uniquingKeysWith: { current, _ in current })
            }
        }
        return SavedSitesEntry(
            date: date,
            data: data,
            isAuthenticated: true,
            faviconDataByWebsiteId: faviconDataByWebsiteId
        )
    }

    private static func fetchFaviconDataByWebsiteId(for websites: [WidgetWebsite]) async -> [String: Data] {
        let candidates = candidateSites(for: websites)
        guard !candidates.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, Data?).self) { group in
            for site in candidates {
                guard let faviconURL = site.resolvedFaviconURL else {
                    continue
                }
                group.addTask {
                    let data = await fetchFaviconData(from: faviconURL)
                    return (site.id, data)
                }
            }

            var results: [String: Data] = [:]
            for await (siteId, maybeData) in group {
                if let data = maybeData {
                    results[siteId] = data
                }
            }
            return results
        }
    }

    private static func fetchFaviconData(from url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  data.count <= 512_000 else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func candidateSites(for websites: [WidgetWebsite]) -> [WidgetWebsite] {
        Array(websites.prefix(SavedSitesWidgetView.maxSites(for: .systemLarge)))
    }

    private func nextMidnight(from date: Date) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return calendar.startOfDay(for: tomorrow)
    }

    private func recordProviderDiagnostics(stage: String, entry: SavedSitesEntry) {
        WidgetExtensionDiagnostics.reporter.recordBreadcrumb(
            surface: "widget_provider",
            stage: stage,
            message: "Built websites widget entry.",
            metadata: [
                "provider": "SavedSitesProvider",
                "is_authenticated": entry.isAuthenticated ? "true" : "false",
                "item_count": "\(entry.data.websites.count)",
                "total_count": "\(entry.data.totalCount)",
                "favicon_count": "\(entry.faviconDataByWebsiteId.count)"
            ]
        )
    }

    static func previewEntry(for family: WidgetFamily, now: Date = Date()) -> SavedSitesEntry {
        SavedSitesEntry(
            date: now,
            data: WidgetGalleryPreviewContent.websites(for: family, now: now),
            isAuthenticated: true,
            faviconDataByWebsiteId: [:]
        )
    }
}
