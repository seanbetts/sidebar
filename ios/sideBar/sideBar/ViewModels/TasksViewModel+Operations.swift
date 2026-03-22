import Foundation

extension TasksViewModel {
    private static let recurringScheduleToastDuration: TimeInterval = 4

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

    @discardableResult
    public func completeTask(task: TaskItem) async -> Bool {
        let operation = TaskOperationPayload(
            operationId: TaskOperationId.make(),
            op: "complete",
            id: task.id,
            clientUpdatedAt: task.updatedAt
        )
        if shouldQueueTaskWrites {
            await queueOfflineOperation(operation)
            return true
        }
        // Optimistically remove the task immediately
        let removedTask = store.removeTask(id: task.id)

        do {
            let response = try await api.apply(TaskOperationBatch(operations: [operation]))
            showNextInstanceScheduledToast(nextTasks: response.nextTasks)
            // Keep UX snappy by relying on optimistic removal + realtime/list refresh.
            // Avoid forcing a full list reload immediately on completion.
            updateCountsAfterLocalOperation(operation)
            Task {
                await loadCounts(force: true)
                await refreshWidgetData()
            }
            return true
        } catch {
            // Restore the task if the API call failed
            if let removedTask {
                store.restoreTask(removedTask)
            }
            setLocalErrorMessage(ErrorMapping.message(for: error))
            return false
        }
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
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "move",
                id: task.id,
                listId: listId,
                clientUpdatedAt: task.updatedAt
            )
        )
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
        if shouldQueueTaskWrites {
            await queueOfflineOperation(operation)
            return
        }
        do {
            let response = try await api.apply(TaskOperationBatch(operations: [operation]))
            showNextInstanceScheduledToast(nextTasks: response.nextTasks)
            if refreshSelection {
                await load(selection: selection, force: true)
            }
            if refreshCounts {
                await loadCounts(force: true)
            }
            if refreshWidget {
                await refreshWidgetData()
            }
        } catch {
            setLocalErrorMessage(ErrorMapping.message(for: error))
        }
    }

    private func queueOfflineOperation(_ operation: TaskOperationPayload) async {
        do {
            try await store.enqueueOperation(operation)
            store.applyLocalOperation(operation)

            // Update widget data and counts optimistically for offline operations
            updateWidgetDataAfterOfflineOperation(operation)
            updateCountsAfterLocalOperation(operation)
        } catch WriteQueueError.queueFull {
            toastCenter.show(message: "Sync queue full. Review pending changes.")
        } catch {
            setLocalErrorMessage("Failed to queue task changes")
        }
    }

    /// Updates widget data optimistically after an offline operation
    private func updateWidgetDataAfterOfflineOperation(_ operation: TaskOperationPayload) {
        // Only update widget for operations that affect "today" view
        guard case .today = selection else {
            // For non-today views, just update with current filtered tasks
            updateWidgetData()
            return
        }

        updateWidgetData()
    }

    /// Updates task counts optimistically after an offline operation
    private func updateCountsAfterLocalOperation(_ operation: TaskOperationPayload) {
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
}
