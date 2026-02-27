import Foundation

extension TasksViewModel {
    public func setErrorMessage(_ message: String) {
        setLocalErrorMessage(message)
    }

    public func completeTask(task: TaskItem) async {
        let operation = TaskOperationPayload(
            operationId: TaskOperationId.make(),
            op: "complete",
            id: task.id,
            clientUpdatedAt: task.updatedAt
        )
        if shouldQueueTaskWrites {
            await queueOfflineOperation(operation)
            return
        }
        // Optimistically remove the task immediately
        let removedTask = store.removeTask(id: task.id)

        do {
            let response = try await api.apply(TaskOperationBatch(operations: [operation]))
            if !response.nextTasks.isEmpty {
                let count = response.nextTasks.count
                let message = count == 1
                    ? "Next instance scheduled: \"\(response.nextTasks[0].title)\""
                    : "\(count) recurring instances scheduled"
                toastCenter.show(message: message)
            }
            // Keep UX snappy by relying on optimistic removal + realtime/list refresh.
            // Avoid forcing a full list reload immediately on completion.
            updateCountsAfterLocalOperation(operation)
            Task {
                await loadCounts(force: true)
                await refreshWidgetData()
            }
        } catch {
            // Restore the task if the API call failed
            if let removedTask {
                store.restoreTask(removedTask)
            }
            setLocalErrorMessage(ErrorMapping.message(for: error))
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
            if !response.nextTasks.isEmpty {
                let count = response.nextTasks.count
                let message = count == 1
                    ? "Next instance scheduled: \"\(response.nextTasks[0].title)\""
                    : "\(count) recurring instances scheduled"
                toastCenter.show(message: message)
            }
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
            // Increment today count for new tasks (if due today)
            if let dueDate = operation.dueDate {
                let today = TasksUtils.formatDateKey(Date())
                if dueDate == today {
                    store.incrementTodayCount()
                }
            } else {
                // No due date defaults to today
                store.incrementTodayCount()
            }
        default:
            break
        }
    }
}
