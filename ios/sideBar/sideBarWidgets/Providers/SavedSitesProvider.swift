import SwiftUI
import WidgetKit

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

    func placeholder(in context: Context) -> SavedSitesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SavedSitesEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task {
            let entry = await createEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SavedSitesEntry>) -> Void) {
        Task {
            let entry = await createEntry()
            // Refresh every 15 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func createEntry() async -> SavedSitesEntry {
        let isAuthenticated = WidgetDataManager.shared.isAuthenticated()
        guard isAuthenticated else {
            return .notAuthenticated
        }

        let data: WidgetWebsiteData = WidgetDataManager.shared.load(for: .websites)
        let faviconDataByWebsiteId = await fetchFaviconDataByWebsiteId(for: data.websites)
        return SavedSitesEntry(
            date: Date(),
            data: data,
            isAuthenticated: true,
            faviconDataByWebsiteId: faviconDataByWebsiteId
        )
    }

    private func fetchFaviconDataByWebsiteId(for websites: [WidgetWebsite]) async -> [String: Data] {
        let candidates = Array(websites.prefix(SavedSitesWidgetView.maxSites(for: .systemLarge)))
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

    private func fetchFaviconData(from url: URL) async -> Data? {
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
}
