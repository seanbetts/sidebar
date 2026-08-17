import Foundation

public enum WidgetTaskPendingCompletionOverlay {
    public static func prepareForNotificationCompletion(
        _ snapshot: WidgetTaskData,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetTaskData {
        guard !calendar.isDate(snapshot.lastUpdated, inSameDayAs: now) else {
            return snapshot
        }
        return WidgetTaskData(
            tasks: snapshot.tasks,
            totalCount: snapshot.totalCount,
            progressCompletedCount: 0,
            progressTotalCount: max(snapshot.totalCount, snapshot.tasks.count),
            optimisticallyCompletedTaskIds: [],
            pendingOptimisticCompletionTaskIds: [],
            lastUpdated: now
        )
    }

    public static func apply(
        to snapshot: WidgetTaskData,
        pendingOperations: [WidgetPendingOperation<TaskWidgetAction>],
        knownDueTodayTaskIds: Set<String> = []
    ) -> WidgetTaskData {
        let completedIds = Set(
            pendingOperations
                .filter { $0.action == .complete && !$0.itemId.isEmpty }
                .map(\.itemId)
        )
        guard !completedIds.isEmpty else {
            return snapshot
        }

        let visibleTaskIds = Set(snapshot.tasks.map(\.id))
        let visibleCompletedIds = completedIds.intersection(visibleTaskIds)
        let knownOffscreenCompletedIds = completedIds
            .intersection(knownDueTodayTaskIds)
            .subtracting(visibleTaskIds)
        let newlyAccountedIds = visibleCompletedIds
            .union(knownOffscreenCompletedIds)
            .subtracting(snapshot.optimisticallyCompletedTaskIds)
        let remainingTasks = snapshot.tasks.filter { !visibleCompletedIds.contains($0.id) }
        guard remainingTasks.count != snapshot.tasks.count || !newlyAccountedIds.isEmpty else {
            return snapshot
        }

        let progressTotalCount = max(snapshot.progressTotalCount, snapshot.totalCount)
        let progressCompletedCount = min(
            progressTotalCount,
            snapshot.progressCompletedCount + newlyAccountedIds.count
        )

        return WidgetTaskData(
            tasks: remainingTasks,
            totalCount: max(0, snapshot.totalCount - newlyAccountedIds.count),
            progressCompletedCount: progressCompletedCount,
            progressTotalCount: progressTotalCount,
            optimisticallyCompletedTaskIds: snapshot.optimisticallyCompletedTaskIds
                .union(newlyAccountedIds),
            pendingOptimisticCompletionTaskIds: snapshot.pendingOptimisticCompletionTaskIds
                .union(newlyAccountedIds),
            lastUpdated: snapshot.lastUpdated
        )
    }

    public static func clearTrackingForReopenedTask(
        _ taskId: String,
        in snapshot: WidgetTaskData
    ) -> WidgetTaskData {
        guard snapshot.optimisticallyCompletedTaskIds.contains(taskId)
                || snapshot.pendingOptimisticCompletionTaskIds.contains(taskId) else {
            return snapshot
        }
        let wasAccounted = snapshot.optimisticallyCompletedTaskIds.contains(taskId)
        return WidgetTaskData(
            tasks: snapshot.tasks,
            totalCount: snapshot.totalCount + (wasAccounted ? 1 : 0),
            progressCompletedCount: snapshot.progressCompletedCount - (wasAccounted ? 1 : 0),
            progressTotalCount: snapshot.progressTotalCount,
            optimisticallyCompletedTaskIds: snapshot.optimisticallyCompletedTaskIds
                .subtracting([taskId]),
            pendingOptimisticCompletionTaskIds: snapshot.pendingOptimisticCompletionTaskIds
                .subtracting([taskId]),
            lastUpdated: snapshot.lastUpdated
        )
    }
}

/// Rebuilds a task-widget snapshot while preserving same-day notification completions.
public enum WidgetTaskSnapshotRefresh {
    public static func reconcile(
        tasks: [WidgetTask],
        previousSnapshot: WidgetTaskData,
        canConfirmCompletionConvergence: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetTaskData {
        let isSameDay = calendar.isDate(previousSnapshot.lastUpdated, inSameDayAs: now)
        let currentTaskIds = Set(tasks.map(\.id))
        let carriedCompletionIds: Set<String>
        let pendingCompletionIds: Set<String>
        let reopenedCompletionIds: Set<String>
        if !isSameDay {
            carriedCompletionIds = []
            pendingCompletionIds = []
            reopenedCompletionIds = []
        } else if canConfirmCompletionConvergence {
            reopenedCompletionIds = previousSnapshot.optimisticallyCompletedTaskIds
                .intersection(currentTaskIds)
                .subtracting(previousSnapshot.pendingOptimisticCompletionTaskIds)
            carriedCompletionIds = previousSnapshot.optimisticallyCompletedTaskIds
                .subtracting(reopenedCompletionIds)
            pendingCompletionIds = previousSnapshot.pendingOptimisticCompletionTaskIds
                .intersection(currentTaskIds)
        } else {
            carriedCompletionIds = previousSnapshot.optimisticallyCompletedTaskIds
            pendingCompletionIds = previousSnapshot.pendingOptimisticCompletionTaskIds
            reopenedCompletionIds = []
        }
        let reconciledTasks = tasks.filter { !pendingCompletionIds.contains($0.id) }
        let remainingCount = reconciledTasks.count

        let progressCompletedCount: Int
        let progressTotalCount: Int
        if isSameDay {
            let persistedCompleted = max(
                0,
                previousSnapshot.progressCompletedCount - reopenedCompletionIds.count
            )
            let persistedTotal = max(0, previousSnapshot.progressTotalCount)
            let nextTotal = max(persistedTotal, remainingCount + persistedCompleted)
            progressTotalCount = nextTotal
            progressCompletedCount = min(
                max(persistedCompleted, nextTotal - remainingCount),
                nextTotal
            )
        } else {
            progressTotalCount = remainingCount
            progressCompletedCount = 0
        }

        return WidgetTaskData(
            tasks: Array(reconciledTasks.prefix(10)),
            totalCount: remainingCount,
            progressCompletedCount: progressCompletedCount,
            progressTotalCount: progressTotalCount,
            optimisticallyCompletedTaskIds: carriedCompletionIds,
            pendingOptimisticCompletionTaskIds: pendingCompletionIds,
            lastUpdated: now
        )
    }
}
