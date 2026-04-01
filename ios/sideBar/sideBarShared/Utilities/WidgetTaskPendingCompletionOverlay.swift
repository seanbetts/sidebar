import Foundation

public enum WidgetTaskPendingCompletionOverlay {
    public static func apply(
        to snapshot: WidgetTaskData,
        pendingOperations: [WidgetPendingOperation<TaskWidgetAction>]
    ) -> WidgetTaskData {
        let completedIds = Set(
            pendingOperations
                .filter { $0.action == .complete && !$0.itemId.isEmpty }
                .map(\.itemId)
        )
        guard !completedIds.isEmpty else {
            return snapshot
        }

        let remainingTasks = snapshot.tasks.filter { !completedIds.contains($0.id) }
        let hiddenCount = snapshot.tasks.count - remainingTasks.count
        guard hiddenCount > 0 else {
            return snapshot
        }

        let progressTotalCount = max(snapshot.progressTotalCount, snapshot.totalCount)
        let progressCompletedCount = min(
            progressTotalCount,
            snapshot.progressCompletedCount + hiddenCount
        )

        return WidgetTaskData(
            tasks: remainingTasks,
            totalCount: max(0, snapshot.totalCount - hiddenCount),
            progressCompletedCount: progressCompletedCount,
            progressTotalCount: progressTotalCount,
            lastUpdated: snapshot.lastUpdated
        )
    }
}
