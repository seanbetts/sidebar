import Foundation

extension TasksViewModel {
    public func startNewTask() {
        let baseSelection = selection.isSearch ? lastNonSearchSelection : selection
        AppSentry.recordAction(
            category: "task",
            name: "Opened New Task Composer",
            data: ["selection_kind": taskSelectionKind(baseSelection)]
        )

        let dueDate: Date?
        if case .upcoming = baseSelection {
            dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        } else {
            dueDate = Date()
        }

        let draftList = draftListContext(for: baseSelection)
        newTaskDraft = TaskDraft(
            title: "",
            notes: "",
            dueDate: dueDate,
            listId: draftList.id,
            listName: draftList.name,
            selection: baseSelection
        )
        newTaskError = ""
    }

    public func cancelNewTask() {
        newTaskDraft = nil
        newTaskError = ""
    }

    public func createTask(title: String, notes: String, dueDate: Date?, listId: String?) async {
        guard !newTaskSaving else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let draft = newTaskDraft else { return }
        guard !trimmed.isEmpty else {
            newTaskError = "Title is required."
            return
        }

        newTaskSaving = true
        newTaskError = ""
        defer { newTaskSaving = false }

        let operation = TaskOperationPayload(
            operationId: TaskOperationId.make(),
            op: "add",
            id: nil,
            title: trimmed,
            notes: normalizedNotesPayload(notes),
            listId: listId ?? draft.listId,
            dueDate: dueDate.map { TasksUtils.formatDateKey($0) },
            startDate: nil,
            recurrenceRule: nil,
            clientUpdatedAt: nil
        )

        if shouldQueueTaskWrites {
            await queueOfflineTaskCreation(operation)
            return
        }

        let snapshot = store.makeOptimisticSnapshot()
        store.applyLocalOperation(operation)
        updateCountsAfterLocalOperation(operation)
        updateWidgetDataAfterOfflineOperation(operation)
        do {
            let response = try await api.apply(TaskOperationBatch(operations: [operation]))
            store.applySyncResponse(response, operationId: operation.operationId)
            newTaskDraft = nil
        } catch {
            store.restoreOptimisticSnapshot(snapshot, operationId: operation.operationId)
            newTaskError = ErrorMapping.message(for: error)
        }
    }

    public func createGroup(title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if shouldQueueTaskWrites {
            try await queueOfflineTaskListOperation(
                TaskOperationPayload(
                    operationId: TaskOperationId.make(),
                    op: "create_group",
                    title: trimmed
                )
            )
            return
        }
        _ = try await api.createGroup(title: trimmed)
        await load(selection: selection, force: true)
        await loadCounts(force: true)
    }

    public func renameGroup(groupId: String, title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if shouldQueueTaskWrites {
            try await queueOfflineTaskListOperation(
                TaskOperationPayload(
                    operationId: TaskOperationId.make(),
                    op: "rename_group",
                    id: groupId,
                    title: trimmed
                )
            )
            return
        }
        _ = try await api.renameGroup(groupId: groupId, title: trimmed)
        await load(selection: selection, force: true)
        await loadCounts(force: true)
    }

    public func deleteGroup(groupId: String) async throws {
        let projectIds = projects.filter { $0.groupId == groupId }.map(\.id)
        let nextSelection: TaskSelection
        switch selection {
        case .group(let id) where id == groupId:
            nextSelection = .none
        case .project(let id) where projectIds.contains(id):
            nextSelection = .none
        default:
            nextSelection = selection
        }

        if shouldQueueTaskWrites {
            try await queueOfflineTaskListOperation(
                TaskOperationPayload(
                    operationId: TaskOperationId.make(),
                    op: "delete_group",
                    id: groupId
                ),
                nextSelection: nextSelection
            )
            return
        }
        try await api.deleteGroup(groupId: groupId)
        await load(selection: nextSelection, force: true)
        await loadCounts(force: true)
    }

    public func createProject(title: String, groupId: String?) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if shouldQueueTaskWrites {
            try await queueOfflineTaskListOperation(
                TaskOperationPayload(
                    operationId: TaskOperationId.make(),
                    op: "create_project",
                    title: trimmed,
                    listId: groupId
                )
            )
            return
        }
        _ = try await api.createProject(title: trimmed, groupId: groupId)
        await load(selection: selection, force: true)
        await loadCounts(force: true)
    }

    public func renameProject(projectId: String, title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if shouldQueueTaskWrites {
            try await queueOfflineTaskListOperation(
                TaskOperationPayload(
                    operationId: TaskOperationId.make(),
                    op: "rename_project",
                    id: projectId,
                    title: trimmed
                )
            )
            return
        }
        _ = try await api.renameProject(projectId: projectId, title: trimmed)
        await load(selection: selection, force: true)
        await loadCounts(force: true)
    }

    public func deleteProject(projectId: String) async throws {
        let nextSelection: TaskSelection
        switch selection {
        case .project(let id) where id == projectId:
            nextSelection = .none
        default:
            nextSelection = selection
        }

        if shouldQueueTaskWrites {
            try await queueOfflineTaskListOperation(
                TaskOperationPayload(
                    operationId: TaskOperationId.make(),
                    op: "delete_project",
                    id: projectId
                ),
                nextSelection: nextSelection
            )
            return
        }
        try await api.deleteProject(projectId: projectId)
        await load(selection: nextSelection, force: true)
        await loadCounts(force: true)
    }

    private func draftListContext(for selection: TaskSelection) -> (id: String?, name: String?) {
        switch selection {
        case .none:
            return (nil, nil)
        case .group(let id):
            return (id, groups.first(where: { $0.id == id })?.title)
        case .project(let id):
            return (id, projects.first(where: { $0.id == id })?.title)
        case .today, .upcoming, .search, .completed:
            if let home = groups.first(where: { $0.title.lowercased() == "home" }) {
                return (home.id, home.title)
            }
            guard let first = groups.first else { return (nil, nil) }
            return (first.id, first.title)
        }
    }

    private func normalizedNotesPayload(_ notes: String) -> String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func queueOfflineTaskCreation(_ operation: TaskOperationPayload) async {
        do {
            try await store.enqueueOperation(operation)
            store.applyLocalOperation(operation)
            updateWidgetDataAfterOfflineOperation(operation)
            updateCountsAfterLocalOperation(operation)
            newTaskDraft = nil
            toastCenter.show(message: "Task queued for sync.")
        } catch WriteQueueError.queueFull {
            newTaskError = "Sync queue full. Review pending changes."
        } catch {
            newTaskError = "Failed to queue task"
        }
    }

    private func queueOfflineTaskListOperation(
        _ operation: TaskOperationPayload,
        nextSelection: TaskSelection? = nil
    ) async throws {
        try await store.enqueueOperation(operation)
        store.applyLocalOperation(operation)
        if let nextSelection, nextSelection != selection {
            await store.load(selection: nextSelection)
        }
    }
}
