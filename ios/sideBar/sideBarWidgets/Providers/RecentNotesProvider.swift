import WidgetKit
import SwiftUI

struct RecentNotesEntry: TimelineEntry {
    let date: Date
    let data: WidgetNoteData
    let isAuthenticated: Bool

    static let placeholder = RecentNotesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true
    )

    static let notAuthenticated = RecentNotesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false
    )
}

struct RecentNotesProvider: TimelineProvider {
    typealias Entry = RecentNotesEntry

    func placeholder(in context: Context) -> RecentNotesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentNotesEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentNotesEntry>) -> Void) {
        let entry = createEntry()

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func createEntry() -> RecentNotesEntry {
        let isAuthenticated = WidgetDataManager.shared.isAuthenticated()
        guard isAuthenticated else {
            return .notAuthenticated
        }

        let data: WidgetNoteData = WidgetDataManager.shared.load(for: .notes)
        return RecentNotesEntry(date: Date(), data: data, isAuthenticated: true)
    }
}
