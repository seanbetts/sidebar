import WidgetKit
import SwiftUI

struct PinnedFilesEntry: TimelineEntry {
    let date: Date
    let data: WidgetFileData
    let isAuthenticated: Bool

    static let placeholder = PinnedFilesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true
    )

    static let notAuthenticated = PinnedFilesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false
    )
}

struct PinnedFilesProvider: TimelineProvider {
    typealias Entry = PinnedFilesEntry

    func placeholder(in context: Context) -> PinnedFilesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedFilesEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedFilesEntry>) -> Void) {
        let entry = createEntry()

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func createEntry() -> PinnedFilesEntry {
        let isAuthenticated = WidgetDataManager.shared.isAuthenticated()
        guard isAuthenticated else {
            return .notAuthenticated
        }

        let data: WidgetFileData = WidgetDataManager.shared.load(for: .files)
        return PinnedFilesEntry(date: Date(), data: data, isAuthenticated: true)
    }
}
