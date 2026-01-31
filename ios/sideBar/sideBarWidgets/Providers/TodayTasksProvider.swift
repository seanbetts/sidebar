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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    func placeholder(in context: Context) -> TodayTasksEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayTasksEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        let entry = createEntry(for: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayTasksEntry>) -> Void) {
        let isAuthenticated = WidgetDataManager.shared.isAuthenticated()
        guard isAuthenticated else {
            let entry = TodayTasksEntry.notAuthenticated
            let timeline = Timeline(entries: [entry], policy: .after(nextMidnight()))
            completion(timeline)
            return
        }

        let data = WidgetDataManager.shared.loadTodayTasks()
        let now = Date()
        var entries: [TodayTasksEntry] = []

        // Entry for right now
        entries.append(TodayTasksEntry(date: now, data: data, isAuthenticated: true))

        // Find unique deadline dates that are today or in the future
        // At midnight, tasks become overdue, so we need entries at those boundaries
        let calendar = Calendar.current
        var boundaryDates: Set<Date> = []

        for task in data.tasks {
            if let deadline = task.deadline,
               deadline.count >= 10,
               let taskDate = Self.dateFormatter.date(from: String(deadline.prefix(10))) {
                // Task becomes overdue at midnight AFTER its due date
                let overdueTime = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: taskDate))
                if let overdueTime, overdueTime > now {
                    boundaryDates.insert(overdueTime)
                }
            }
        }

        // Always add next midnight for general refresh
        let nextMidnightDate = nextMidnight()
        boundaryDates.insert(nextMidnightDate)

        // Sort and limit to prevent excessive entries (iOS has timeline budget)
        let sortedBoundaries = boundaryDates.sorted().prefix(5)

        for boundaryDate in sortedBoundaries {
            // Create entry with same data but different date
            // The widget will re-evaluate isOverdue based on the entry date
            entries.append(TodayTasksEntry(date: boundaryDate, data: data, isAuthenticated: true))
        }

        // Use .after policy for the last boundary + 15 minutes to trigger a fresh data fetch
        let lastEntry = sortedBoundaries.last ?? nextMidnightDate
        let nextRefresh = calendar.date(byAdding: .minute, value: 15, to: lastEntry) ?? lastEntry
        let timeline = Timeline(entries: entries, policy: .after(nextRefresh))
        completion(timeline)
    }

    private func createEntry(for date: Date) -> TodayTasksEntry {
        let isAuthenticated = WidgetDataManager.shared.isAuthenticated()
        guard isAuthenticated else {
            return .notAuthenticated
        }

        let data = WidgetDataManager.shared.loadTodayTasks()
        return TodayTasksEntry(date: date, data: data, isAuthenticated: true)
    }

    private func nextMidnight() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.startOfDay(for: tomorrow)
    }
}
