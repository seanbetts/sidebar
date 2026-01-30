import SwiftUI
import WidgetKit

struct SavedSitesEntry: TimelineEntry {
    let date: Date
    let data: WidgetWebsiteData
    let isAuthenticated: Bool

    static let placeholder = SavedSitesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true
    )

    static let notAuthenticated = SavedSitesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false
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

        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SavedSitesEntry>) -> Void) {
        let entry = createEntry()

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func createEntry() -> SavedSitesEntry {
        let isAuthenticated = WidgetDataManager.shared.isAuthenticated()
        guard isAuthenticated else {
            return .notAuthenticated
        }

        let data: WidgetWebsiteData = WidgetDataManager.shared.load(for: .websites)
        return SavedSitesEntry(date: Date(), data: data, isAuthenticated: true)
    }
}
