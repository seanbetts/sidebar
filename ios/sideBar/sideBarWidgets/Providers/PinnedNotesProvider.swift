import WidgetKit
import SwiftUI

struct PinnedNotesEntry: TimelineEntry {
    let date: Date
    let data: WidgetNoteData
    let isAuthenticated: Bool

    static let placeholder = PinnedNotesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true
    )

    static let notAuthenticated = PinnedNotesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false
    )
}

struct PinnedNotesProvider: TimelineProvider {
    typealias Entry = PinnedNotesEntry

    func placeholder(in context: Context) -> PinnedNotesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedNotesEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedNotesEntry>) -> Void) {
        let entry = createEntry()

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func createEntry() -> PinnedNotesEntry {
        let isAuthenticated = WidgetDataManager.shared.isAuthenticated()
        guard isAuthenticated else {
            return .notAuthenticated
        }

        let data: WidgetNoteData = WidgetDataManager.shared.load(for: .notes)
        return PinnedNotesEntry(date: Date(), data: data, isAuthenticated: true)
    }
}
