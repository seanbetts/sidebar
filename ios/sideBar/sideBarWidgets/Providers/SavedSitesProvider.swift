import SwiftUI
import WidgetKit
import sideBarShared

struct SavedSitesEntry: TimelineEntry {
    let date: Date
    let data: WidgetWebsiteData
    let isAuthenticated: Bool
    let faviconDataByWebsiteId: [String: Data]
    let selection: WebsiteWidgetSelection

    static let placeholder = SavedSitesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true,
        faviconDataByWebsiteId: [:],
        selection: .all
    )

    static let notAuthenticated = SavedSitesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false,
        faviconDataByWebsiteId: [:],
        selection: .all
    )
}

struct SavedSitesProvider: AppIntentTimelineProvider {
    typealias Intent = WebsitesWidgetConfigurationIntent
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
        Self.previewEntry(for: context.family, selection: .all, now: now())
    }

    func snapshot(for configuration: WebsitesWidgetConfigurationIntent, in context: Context) async -> SavedSitesEntry {
        if context.isPreview {
            return Self.previewEntry(for: context.family, selection: configuration.selection, now: now())
        }

        let entry = await entry(for: now(), selection: configuration.selection)
        recordProviderDiagnostics(stage: "snapshot", entry: entry)
        return entry
    }

    func timeline(
        for configuration: WebsitesWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<SavedSitesEntry> {
        await timeline(for: now(), selection: configuration.selection)
    }

    func timeline(
        for currentDate: Date,
        selection: WebsiteWidgetSelection = .all
    ) async -> Timeline<SavedSitesEntry> {
        let entry = await entry(for: currentDate, selection: selection)
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

    func entry(
        for date: Date,
        selection: WebsiteWidgetSelection = .all
    ) async -> SavedSitesEntry {
        let hasCachedSnapshot = dataManager.hasStoredSnapshot(for: .websites)
        let isAuthenticated = dataManager.isAuthenticated()
        let canDisplayContent = WidgetDisplayAuthorization.canDisplayContent(
            isAuthenticated: isAuthenticated,
            hasCachedSnapshot: hasCachedSnapshot
        )
        guard canDisplayContent else {
            return .notAuthenticated
        }

        let storedData: WidgetWebsiteData = dataManager.load(for: .websites)
        var data: WidgetWebsiteData = selection.filter(storedData)
        let decision = WidgetRefreshCoordinator.decision(
            contentType: .websites,
            lastUpdated: hasCachedSnapshot ? storedData.lastUpdated : nil,
            hasCachedSnapshot: hasCachedSnapshot,
            isAuthenticated: isAuthenticated,
            now: date
        )

        if decision.shouldAttemptRefresh {
            do {
                let refreshed = try await refreshData(date)
                dataManager.store(refreshed, for: .websites)
                data = selection.filter(refreshed)
            } catch {
                let appError = AppError.classify(
                    error: error,
                    operation: "widget.websites.refresh",
                    requestKind: .widgetRefresh
                )
                var metadata = appError.diagnostics
                metadata["provider"] = "SavedSitesProvider"
                metadata["selection"] = selection.headerTitle
                metadata["has_cached_snapshot"] = hasCachedSnapshot ? "true" : "false"
                WidgetExtensionDiagnostics.reporter.captureFailure(
                    surface: "widget_provider",
                    stage: "saved_sites_refresh_failed",
                    message: "Failed to refresh websites widget content.",
                    metadata: metadata
                )
            }
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
            faviconDataByWebsiteId: faviconDataByWebsiteId,
            selection: selection
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

    static func previewEntry(
        for family: WidgetFamily,
        selection: WebsiteWidgetSelection = .all,
        now: Date = Date()
    ) -> SavedSitesEntry {
        let previewData = selection.filter(WidgetGalleryPreviewContent.websites(for: family, now: now))
        return SavedSitesEntry(
            date: now,
            data: previewData,
            isAuthenticated: true,
            faviconDataByWebsiteId: [:],
            selection: selection
        )
    }
}
