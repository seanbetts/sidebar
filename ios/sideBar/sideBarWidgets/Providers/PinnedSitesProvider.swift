import SwiftUI
import WidgetKit

struct PinnedSitesEntry: TimelineEntry {
    let date: Date
    let data: WidgetWebsiteData
    let isAuthenticated: Bool

    static let placeholder = PinnedSitesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true
    )

    static let notAuthenticated = PinnedSitesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false
    )
}

struct PinnedSitesProvider: TimelineProvider {
    typealias Entry = PinnedSitesEntry

    func placeholder(in context: Context) -> PinnedSitesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedSitesEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedSitesEntry>) -> Void) {
        let entry = createEntry()

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func createEntry() -> PinnedSitesEntry {
        let isAuthenticated = WidgetDataManager.shared.isAuthenticated()
        guard isAuthenticated else {
            return .notAuthenticated
        }

        let data: WidgetWebsiteData = WidgetDataManager.shared.load(for: .websites)
        return PinnedSitesEntry(date: Date(), data: data, isAuthenticated: true)
    }
}
