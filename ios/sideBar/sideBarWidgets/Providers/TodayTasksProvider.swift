import WidgetKit
import SwiftUI
import sideBarShared

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

    private let dataManager: WidgetDataManager
    private let now: () -> Date
    private let refreshData: @Sendable (WidgetTaskData, Date) async throws -> WidgetTaskData

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    init(
        dataManager: WidgetDataManager = .shared,
        now: @escaping () -> Date = Date.init,
        refreshData: @escaping @Sendable (WidgetTaskData, Date) async throws -> WidgetTaskData = { cached, currentDate in
            let environment = try WidgetAPIEnvironment()
            return try await TasksWidgetRefreshClient(environment: environment)
                .refreshTodayTasks(previousSnapshot: cached, now: currentDate)
        }
    ) {
        self.dataManager = dataManager
        self.now = now
        self.refreshData = refreshData
    }

    func placeholder(in context: Context) -> TodayTasksEntry {
        Self.previewEntry(for: context.family, now: now())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayTasksEntry) -> Void) {
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

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayTasksEntry>) -> Void) {
        Task {
            completion(await timeline(for: now()))
        }
    }

    func timeline(for currentDate: Date) async -> Timeline<TodayTasksEntry> {
        let entry = await entry(for: currentDate)
        guard entry.isAuthenticated else {
            recordProviderDiagnostics(stage: "timeline", entry: entry)
            return Timeline(entries: [entry], policy: .after(nextMidnight(from: currentDate)))
        }

        var entries: [TodayTasksEntry] = [entry]
        let calendar = Calendar.current
        var boundaryDates: Set<Date> = []

        for task in entry.data.tasks {
            if let completionBoundary = WidgetTasksUtils.completionRemovalDate(for: task),
               completionBoundary > currentDate {
                boundaryDates.insert(completionBoundary)
            }
            if let deadline = task.deadline,
               deadline.count >= 10,
               let taskDate = Self.dateFormatter.date(from: String(deadline.prefix(10))) {
                let overdueTime = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: calendar.startOfDay(for: taskDate)
                )
                if let overdueTime, overdueTime > currentDate {
                    boundaryDates.insert(overdueTime)
                }
            }
        }

        let nextMidnightDate = nextMidnight(from: currentDate)
        boundaryDates.insert(nextMidnightDate)

        let sortedBoundaries = boundaryDates.sorted().prefix(5)
        for boundaryDate in sortedBoundaries {
            entries.append(
                TodayTasksEntry(
                    date: boundaryDate,
                    data: entry.data,
                    isAuthenticated: true
                )
            )
        }

        let lastEntry = sortedBoundaries.last ?? nextMidnightDate
        let nextRefresh = calendar.date(byAdding: .minute, value: 15, to: lastEntry) ?? lastEntry
        recordProviderDiagnostics(stage: "timeline", entry: entries.first ?? .notAuthenticated)
        return Timeline(entries: entries, policy: .after(nextRefresh))
    }

    func entry(for date: Date) async -> TodayTasksEntry {
        let hasCachedSnapshot = dataManager.hasStoredSnapshot(for: .tasks)
        let isAuthenticated = dataManager.isAuthenticated()
        let canDisplayContent = WidgetDisplayAuthorization.canDisplayContent(
            isAuthenticated: isAuthenticated,
            hasCachedSnapshot: hasCachedSnapshot
        )
        guard canDisplayContent else {
            return .notAuthenticated
        }

        var data = dataManager.loadTodayTasks()
        let decision = WidgetRefreshCoordinator.decision(
            contentType: .tasks,
            lastUpdated: hasCachedSnapshot ? data.lastUpdated : nil,
            hasCachedSnapshot: hasCachedSnapshot,
            isAuthenticated: isAuthenticated,
            now: date
        )

        if decision.shouldAttemptRefresh {
            do {
                let refreshed = try await refreshData(data, date)
                let pending = dataManager.loadPendingOperations(
                    for: .tasks,
                    actionType: TaskWidgetAction.self
                )
                let overlaid = WidgetTaskPendingCompletionOverlay.apply(
                    to: refreshed,
                    pendingOperations: pending
                )
                dataManager.store(overlaid, for: .tasks)
                data = overlaid
            } catch {}
        }

        return TodayTasksEntry(date: date, data: data, isAuthenticated: true)
    }

    private func nextMidnight(from date: Date) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return calendar.startOfDay(for: tomorrow)
    }

    private func recordProviderDiagnostics(stage: String, entry: TodayTasksEntry) {
        WidgetExtensionDiagnostics.reporter.recordBreadcrumb(
            surface: "widget_provider",
            stage: stage,
            message: "Built task widget entry.",
            metadata: [
                "provider": "TodayTasksProvider",
                "is_authenticated": entry.isAuthenticated ? "true" : "false",
                "item_count": "\(entry.data.tasks.count)",
                "total_count": "\(entry.data.totalCount)"
            ]
        )
    }

    static func previewEntry(for family: WidgetFamily, now: Date = Date()) -> TodayTasksEntry {
        TodayTasksEntry(
            date: now,
            data: WidgetGalleryPreviewContent.tasks(for: family, now: now),
            isAuthenticated: true
        )
    }
}
