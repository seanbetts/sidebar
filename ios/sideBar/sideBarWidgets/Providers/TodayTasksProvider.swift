import WidgetKit
import SwiftUI
import sideBarShared

struct TodayTasksEntry: TimelineEntry {
    let date: Date
    let data: WidgetTaskData
    let isAuthenticated: Bool
    let selection: TaskWidgetSelection

    static let placeholder = TodayTasksEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true,
        selection: .today
    )

    static let notAuthenticated = TodayTasksEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false,
        selection: .today
    )
}

struct TodayTasksProvider: AppIntentTimelineProvider {
    typealias Intent = TaskWidgetConfigurationIntent
    typealias Entry = TodayTasksEntry

    private let dataManager: WidgetDataManager
    private let now: () -> Date
    private let refreshData: @Sendable (WidgetTaskData, TaskWidgetSelection, Date) async throws -> WidgetTaskData

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
        refreshData: @escaping @Sendable (
            WidgetTaskData,
            TaskWidgetSelection,
            Date
        ) async throws -> WidgetTaskData = { cached, selection, currentDate in
            let environment = try WidgetAPIEnvironment()
            return try await TasksWidgetRefreshClient(environment: environment)
                .refreshTasks(previousSnapshot: cached, selection: selection, now: currentDate)
        }
    ) {
        self.dataManager = dataManager
        self.now = now
        self.refreshData = refreshData
    }

    func placeholder(in context: Context) -> TodayTasksEntry {
        Self.previewEntry(for: context.family, selection: .today, now: now())
    }

    func snapshot(for configuration: TaskWidgetConfigurationIntent, in context: Context) async -> TodayTasksEntry {
        if context.isPreview {
            return Self.previewEntry(for: context.family, selection: configuration.selection, now: now())
        }

        let entry = await entry(for: now(), selection: configuration.selection)
        recordProviderDiagnostics(stage: "snapshot", entry: entry)
        return entry
    }

    func timeline(for configuration: TaskWidgetConfigurationIntent, in context: Context) async -> Timeline<TodayTasksEntry> {
        await timeline(for: now(), selection: configuration.selection)
    }

    func timeline(for currentDate: Date, selection: TaskWidgetSelection = .today) async -> Timeline<TodayTasksEntry> {
        let entry = await entry(for: currentDate, selection: selection)
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
                    isAuthenticated: true,
                    selection: entry.selection
                )
            )
        }

        let lastEntry = sortedBoundaries.last ?? nextMidnightDate
        let nextRefresh = calendar.date(byAdding: .minute, value: 15, to: lastEntry) ?? lastEntry
        recordProviderDiagnostics(stage: "timeline", entry: entries.first ?? .notAuthenticated)
        return Timeline(entries: entries, policy: .after(nextRefresh))
    }

    func entry(for date: Date, selection: TaskWidgetSelection = .today) async -> TodayTasksEntry {
        let hasCachedSnapshot = dataManager.hasStoredTaskSnapshot(for: selection)
        let isAuthenticated = dataManager.isAuthenticated()
        let canDisplayContent = WidgetDisplayAuthorization.canDisplayContent(
            isAuthenticated: isAuthenticated,
            hasCachedSnapshot: hasCachedSnapshot
        )
        guard canDisplayContent else {
            return .notAuthenticated
        }

        var data = dataManager.loadTaskData(for: selection)
        let decision = WidgetRefreshCoordinator.decision(
            contentType: .tasks,
            lastUpdated: hasCachedSnapshot ? data.lastUpdated : nil,
            hasCachedSnapshot: hasCachedSnapshot,
            isAuthenticated: isAuthenticated,
            now: date
        )
        let shouldAttemptScopedEmptyRefresh =
            selection != .today &&
            data.tasks.isEmpty

        if decision.shouldAttemptRefresh || shouldAttemptScopedEmptyRefresh {
            do {
                let refreshed = try await refreshData(data, selection, date)
                let pending = dataManager.loadPendingOperations(
                    for: .tasks,
                    actionType: TaskWidgetAction.self
                )
                let overlaid = WidgetTaskPendingCompletionOverlay.apply(
                    to: refreshed,
                    pendingOperations: pending
                )
                dataManager.storeTaskData(overlaid, for: selection)
                data = overlaid
            } catch {
                let appError = AppError.classify(
                    error: error,
                    operation: "widget.tasks.refresh",
                    requestKind: .widgetRefresh
                )
                var metadata = appError.diagnostics
                metadata["provider"] = "TodayTasksProvider"
                metadata["selection"] = selection.headerTitle
                metadata["scope"] = selection.cacheKey
                metadata["has_cached_snapshot"] = hasCachedSnapshot ? "true" : "false"
                WidgetExtensionDiagnostics.reporter.captureFailure(
                    surface: "widget_provider",
                    stage: "today_tasks_refresh_failed",
                    message: "Failed to refresh task widget content.",
                    metadata: metadata
                )
            }
        }

        return TodayTasksEntry(date: date, data: data, isAuthenticated: true, selection: selection)
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

    static func previewEntry(
        for family: WidgetFamily,
        selection: TaskWidgetSelection = .today,
        now: Date = Date()
    ) -> TodayTasksEntry {
        TodayTasksEntry(
            date: now,
            data: WidgetGalleryPreviewContent.tasks(for: family, now: now),
            isAuthenticated: true,
            selection: selection
        )
    }
}
