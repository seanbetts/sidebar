import Foundation
import sideBarShared

enum TaskNotificationCompletionFailure: Equatable {
    case queueFull
    case unavailable
}

enum TaskNotificationCompletionResult: Equatable {
    case queued
    case failed(TaskNotificationCompletionFailure)

    var isQueued: Bool {
        self == .queued
    }
}

extension TasksViewModel {
    private static let recurringScheduleToastDuration: TimeInterval = 4

    private enum MutationFailurePresentation {
        case foreground
        case silent
    }

    func taskSelectionKind(_ selection: TaskSelection) -> String {
        switch selection {
        case .none:
            return "none"
        case .today:
            return "today"
        case .upcoming:
            return "upcoming"
        case .completed:
            return "completed"
        case .search:
            return "search"
        case .group:
            return "group"
        case .project:
            return "project"
        }
    }

    public func setErrorMessage(_ message: String) {
        setLocalErrorMessage(message)
    }

    private func presentMutationFailure(_ error: Error, operation: String) {
        let presentation = ErrorMapping.presentation(
            for: error,
            operation: operation,
            requestKind: .foregroundMutation
        )

        switch presentation.surface {
        case .inline, .placeholder:
            setLocalErrorMessage(presentation.message)
        case .silent:
            setLocalErrorMessage(nil)
        default:
            setLocalErrorMessage(nil)
            toastCenter.show(message: presentation.message)
        }
    }

    @discardableResult
    public func completeTask(task: TaskItem) async -> Bool {
        let result = await queueTaskCompletion(
            taskId: task.id,
            clientUpdatedAt: task.updatedAt,
            refreshWidget: true,
            failurePresentation: .foreground
        )
        return result.isQueued
    }

    @discardableResult
    func completeDueTodayTaskFromNotification(
        taskId: String,
        beforeEnqueue: (@MainActor @Sendable () async -> Void)? = nil
    ) async -> TaskNotificationCompletionResult {
        let existingSnapshot = WidgetTaskPendingCompletionOverlay.prepareForNotificationCompletion(
            widgetDataManager.loadTaskData(for: .today)
        )
        if existingSnapshot.optimisticallyCompletedTaskIds.contains(taskId)
            || inFlightTaskNotificationCompletionIds.contains(taskId) {
            return .queued
        }
        inFlightTaskNotificationCompletionIds.insert(taskId)
        defer { inFlightTaskNotificationCompletionIds.remove(taskId) }
        await beforeEnqueue?()
        let result = await queueTaskCompletion(
            taskId: taskId,
            clientUpdatedAt: nil,
            refreshWidget: selection != .today,
            failurePresentation: .silent
        )
        if result.isQueued {
            let latestSnapshot = WidgetTaskPendingCompletionOverlay.prepareForNotificationCompletion(
                widgetDataManager.loadTaskData(for: .today)
            )
            updateTodayWidgetSnapshotAfterCompletion(
                taskId: taskId,
                snapshot: latestSnapshot
            )
        }
        return result
    }

    private func queueTaskCompletion(
        taskId: String,
        clientUpdatedAt: String?,
        refreshWidget: Bool,
        failurePresentation: MutationFailurePresentation
    ) async -> TaskNotificationCompletionResult {
        let operation = TaskOperationPayload(
            operationId: TaskOperationId.make(),
            op: "complete",
            id: taskId,
            clientUpdatedAt: clientUpdatedAt
        )
        return await queueLocalFirstOperationResult(
            operation,
            refreshWidget: refreshWidget,
            failurePresentation: failurePresentation
        )
    }

    private func updateTodayWidgetSnapshotAfterCompletion(
        taskId: String,
        snapshot: WidgetTaskData
    ) {
        let operation = WidgetPendingOperation(
            itemId: taskId,
            action: TaskWidgetAction.complete
        )
        let updated = WidgetTaskPendingCompletionOverlay.apply(
            to: snapshot,
            pendingOperations: [operation],
            knownDueTodayTaskIds: [taskId]
        )
        widgetDataManager.storeTaskData(updated, for: .today)
    }

    @discardableResult
    public func reopenTask(task: TaskItem) async -> Bool {
        let operation = TaskOperationPayload(
            operationId: TaskOperationId.make(),
            op: "reopen",
            id: task.id,
            clientUpdatedAt: task.updatedAt
        )
        let shouldIncrementTodayCount = reopenedTaskBelongsInToday(task)
        setLocalErrorMessage(nil)

        let queued = await queueLocalFirstOperation(operation)
        if queued, shouldIncrementTodayCount {
            store.incrementTodayCount()
            clearTodayWidgetCompletionTrackingAfterReopen(taskId: task.id)
        }
        return queued
    }

    private func clearTodayWidgetCompletionTrackingAfterReopen(taskId: String) {
        let snapshot = widgetDataManager.loadTaskData(for: .today)
        let updated = WidgetTaskPendingCompletionOverlay.clearTrackingForReopenedTask(
            taskId,
            in: snapshot
        )
        guard updated != snapshot else { return }
        widgetDataManager.storeTaskData(updated, for: .today)
    }

    public func renameTask(task: TaskItem, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "rename",
                id: task.id,
                title: trimmed,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func updateNotes(task: TaskItem, notes: String) async {
        await applyNotesOperation(task: task, notes: notes, refreshAfterSave: true)
    }

    public func autosaveNotes(task: TaskItem, notes: String) async {
        await applyNotesOperation(task: task, notes: notes, refreshAfterSave: false)
    }

    private func applyNotesOperation(task: TaskItem, notes: String, refreshAfterSave: Bool) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "notes",
                id: task.id,
                notes: notes,
                clientUpdatedAt: task.updatedAt
            ),
            refreshSelection: refreshAfterSave,
            refreshCounts: refreshAfterSave,
            refreshWidget: refreshAfterSave
        )
    }

    public func moveTask(task: TaskItem, listId: String?) async {
        let operation = TaskOperationPayload(
            operationId: TaskOperationId.make(),
            op: "move",
            id: task.id,
            listId: listId,
            clientUpdatedAt: task.updatedAt
        )
        setLocalErrorMessage(nil)
        await queueLocalFirstOperation(operation)
    }

    public func setDueDate(task: TaskItem, date: Date?) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "set_due",
                id: task.id,
                dueDate: date.map { TasksUtils.formatDateKey($0) },
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func deferTask(task: TaskItem, days: Int) async {
        let baseDate = TasksUtils.parseTaskDate(task) ?? Date()
        let nextDate = Calendar.current.date(byAdding: .day, value: days, to: baseDate) ?? baseDate
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "defer",
                id: task.id,
                dueDate: TasksUtils.formatDateKey(nextDate),
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func clearDueDate(task: TaskItem) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "clear_due",
                id: task.id,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func setRepeat(task: TaskItem, rule: RecurrenceRule?, startDate: Date?) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "set_repeat",
                id: task.id,
                startDate: startDate.map { TasksUtils.formatDateKey($0) },
                recurrenceRule: rule,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func deleteTask(task: TaskItem) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "trash",
                id: task.id,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    private func applyTaskOperation(
        _ operation: TaskOperationPayload,
        refreshSelection: Bool = true,
        refreshCounts: Bool = true,
        refreshWidget: Bool = true
    ) async {
        setLocalErrorMessage(nil)
        _ = refreshSelection
        _ = refreshCounts
        await queueLocalFirstOperation(operation, refreshWidget: refreshWidget)
    }

    @discardableResult
    private func queueLocalFirstOperation(
        _ operation: TaskOperationPayload,
        refreshWidget: Bool = true
    ) async -> Bool {
        await queueLocalFirstOperationResult(
            operation,
            refreshWidget: refreshWidget,
            failurePresentation: .foreground
        ).isQueued
    }

    private func queueLocalFirstOperationResult(
        _ operation: TaskOperationPayload,
        refreshWidget: Bool = true,
        failurePresentation: MutationFailurePresentation
    ) async -> TaskNotificationCompletionResult {
        do {
            try await store.enqueueOperation(operation)
            store.applyLocalOperation(operation)

            // Update widget data and counts optimistically for queued operations.
            if refreshWidget {
                updateWidgetDataAfterOfflineOperation(operation)
            }
            updateCountsAfterLocalOperation(operation)
            return .queued
        } catch WriteQueueError.queueFull {
            if failurePresentation == .foreground {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
            }
            return .failed(.queueFull)
        } catch {
            if failurePresentation == .foreground {
                setLocalErrorMessage("Failed to queue task changes")
            }
            return .failed(.unavailable)
        }
    }

    /// Updates widget data optimistically after an offline operation
    func updateWidgetDataAfterOfflineOperation(_ operation: TaskOperationPayload) {
        // Only update widget for operations that affect "today" view
        guard case .today = selection else {
            // For non-today views, just update with current filtered tasks
            updateWidgetData()
            return
        }

        updateWidgetData()
    }

    /// Updates task counts optimistically after an offline operation
    func updateCountsAfterLocalOperation(_ operation: TaskOperationPayload) {
        guard counts != nil else { return }

        switch operation.op.lowercased() {
        case "complete", "trash":
            // Decrement today count for completed/deleted tasks
            store.decrementTodayCount()
        case "add":
            if let dueDate = operation.dueDate {
                let today = TasksUtils.formatDateKey(Date())
                if dueDate == today {
                    store.incrementTodayCount()
                }
            }
        default:
            break
        }
    }

    private func showNextInstanceScheduledToast(nextTasks: [TaskItem]) {
        guard !nextTasks.isEmpty else { return }
        let count = nextTasks.count
        let message: String
        if count == 1, let nextTask = nextTasks.first {
            if let date = nextScheduledDateText(for: nextTask) {
                message = "\(nextTask.title) next scheduled for \(date)"
            } else {
                message = "Next instance scheduled: \(nextTask.title)"
            }
        } else if let nextDate = nextTasks.compactMap({ nextScheduledDateKey(for: $0) }).min() {
            message = "\(count) recurring instances scheduled (next: \(nextDate))"
        } else {
            message = "\(count) recurring instances scheduled"
        }
        toastCenter.show(
            message: message,
            style: .success,
            duration: Self.recurringScheduleToastDuration
        )
    }

    private func nextScheduledDateKey(for task: TaskItem) -> String? {
        if let deadline = task.deadline, deadline.count >= 10 {
            return String(deadline.prefix(10))
        }
        if let nextInstanceDate = task.nextInstanceDate, nextInstanceDate.count >= 10 {
            return String(nextInstanceDate.prefix(10))
        }
        return nil
    }

    private func nextScheduledDateText(for task: TaskItem) -> String? {
        if let date = TasksUtils.parseTaskDate(task) {
            return date.formatted(.dateTime.day().month(.wide))
        }
        guard
            let nextInstanceDate = task.nextInstanceDate,
            nextInstanceDate.count >= 10
        else {
            return nil
        }
        let dateKey = String(nextInstanceDate.prefix(10))
        guard let date = TasksUtils.tasksDateFormatter.date(from: dateKey) else {
            return nil
        }
        return date.formatted(.dateTime.day().month(.wide))
    }

    private func reopenedTaskBelongsInToday(_ task: TaskItem) -> Bool {
        guard let deadline = TasksUtils.parseTaskDate(task) else { return false }
        return deadline <= Calendar.current.startOfDay(for: Date())
    }
}
