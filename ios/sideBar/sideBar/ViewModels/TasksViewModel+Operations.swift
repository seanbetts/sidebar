import Foundation

extension TasksViewModel {
    public func setErrorMessage(_ message: String) {
        errorMessage = message
    }

    public func completeTask(task: TaskItem) async {
        // Optimistically remove the task immediately
        let removedTask = store.removeTask(id: task.id)

        do {
            let response = try await api.apply(TaskOperationBatch(operations: [
                TaskOperationPayload(
                    operationId: TaskOperationId.make(),
                    op: "complete",
                    id: task.id,
                    clientUpdatedAt: task.updatedAt
                )
            ]))
            if !response.nextTasks.isEmpty {
                let count = response.nextTasks.count
                let message = count == 1
                    ? "Next instance scheduled: \"\(response.nextTasks[0].title)\""
                    : "\(count) recurring instances scheduled"
                toastCenter.show(message: message)
            }
            // Confirm removal and refresh in background to sync with server
            store.confirmRemoval(id: task.id)
            Task {
                await load(selection: selection, force: true)
                await loadCounts(force: true)
            }
        } catch {
            // Restore the task if the API call failed
            if let removedTask {
                store.restoreTask(removedTask)
            }
            errorMessage = ErrorMapping.message(for: error)
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
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "notes",
                id: task.id,
                notes: notes,
                clientUpdatedAt: task.updatedAt
            )
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

    private func applyTaskOperation(_ operation: TaskOperationPayload) async {
        errorMessage = nil
        do {
            let response = try await api.apply(TaskOperationBatch(operations: [operation]))
            if !response.nextTasks.isEmpty {
                let count = response.nextTasks.count
                let message = count == 1
                    ? "Next instance scheduled: \"\(response.nextTasks[0].title)\""
                    : "\(count) recurring instances scheduled"
                toastCenter.show(message: message)
            }
            await load(selection: selection, force: true)
            await loadCounts(force: true)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }
}
