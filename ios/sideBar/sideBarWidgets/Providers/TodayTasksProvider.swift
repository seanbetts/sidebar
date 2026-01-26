import WidgetKit
import SwiftUI

struct TodayTasksEntry: TimelineEntry {
    let date: Date
    let data: WidgetTaskData
    let isAuthenticated: Bool

    static let placeholder = TodayTasksEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true
    )

    static let notAuthenticated = TodayTasksEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false
    )
}

struct TodayTasksProvider: TimelineProvider {
    typealias Entry = TodayTasksEntry

    func placeholder(in context: Context) -> TodayTasksEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayTasksEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayTasksEntry>) -> Void) {
        let entry = createEntry()

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func createEntry() -> TodayTasksEntry {
        let isAuthenticated = WidgetDataManager.shared.isAuthenticated()
        guard isAuthenticated else {
            return .notAuthenticated
        }

        let data = WidgetDataManager.shared.loadTodayTasks()
        return TodayTasksEntry(date: Date(), data: data, isAuthenticated: true)
    }
}
