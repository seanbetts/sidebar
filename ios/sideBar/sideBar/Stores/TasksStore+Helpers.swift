import Foundation

extension TasksStore {
    func indexTasksInSpotlight(_ items: [TaskItem]) {
        guard let indexer = spotlightIndexer else { return }
        let spotlightTasks = items
            .filter { $0.deletedAt == nil && !$0.isPreview }
            .map { item in
                SpotlightTask(
                    id: item.id,
                    title: item.title,
                    notes: item.notes,
                    status: item.status,
                    deadline: item.deadline
                )
            }
        Task {
            await indexer.indexTasks(spotlightTasks)
        }
    }

    func removeTaskFromSpotlight(id: String) {
        guard let indexer = spotlightIndexer else { return }
        Task {
            await indexer.removeTask(id: id)
        }
    }

    func enqueueOperation(_ operation: TaskOperationPayload) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        try await writeQueue.enqueue(
            operation: .update,
            entityType: .task,
            entityId: operation.id,
            payload: operation
        )
    }

    func enqueueBatch(_ batch: TaskOperationBatch) async throws {
        for operation in batch.operations {
            try await enqueueOperation(operation)
        }
    }

    struct OptimisticSnapshot {
        let tasks: [TaskItem]
        let projects: [TaskProject]
        let groups: [TaskGroup]
        let counts: TaskCountsResponse?
        let pendingRemovals: Set<String>
    }

    func makeOptimisticSnapshot() -> OptimisticSnapshot {
        OptimisticSnapshot(
            tasks: tasks,
            projects: projects,
            groups: groups,
            counts: counts,
            pendingRemovals: pendingRemovals
        )
    }

    func restoreOptimisticSnapshot(_ snapshot: OptimisticSnapshot, operationId: String? = nil) {
        tasks = snapshot.tasks
        projects = snapshot.projects
        groups = snapshot.groups
        counts = snapshot.counts
        pendingRemovals = snapshot.pendingRemovals
        if let operationId {
            removePendingTaskRegistration(operationId: operationId)
        }
        persistCurrentSnapshot()
    }

    func applyLocalOperation(_ operation: TaskOperationPayload) {
        guard let kind = localOperation(from: operation.op) else { return }
        applyLocalOperation(operation, kind: kind)
        reconcileVisibilityAfterLocalOperation(operation, kind: kind)
        persistCurrentSnapshot()
    }

    func applySyncResponse(_ response: TaskSyncResponse, operationId: String) {
        if response.applied.contains(operationId) {
            removePendingTaskPlaceholder(operationId: operationId)
        }
        if let updates = response.updates {
            mergeProjects(updates.projects)
            mergeGroups(updates.groups)
            applyServerTasks(updates.tasks)
        }
        applyServerTasks(response.tasks + response.nextTasks)
        persistCurrentSnapshot()
    }

    func removePendingTaskPlaceholder(operationId: String) {
        guard let offlineStore else { return }
        let key = pendingTaskKey(operationId: operationId)
        guard let placeholderId = offlineStore.get(key: key, as: String.self) else { return }
        tasks.removeAll { $0.id == placeholderId }
        offlineStore.remove(key: key)
    }

    func lastSyncToken() -> String? {
        offlineStore?.get(key: CacheKeys.tasksSync, as: String.self)
    }

    func updateLastSyncToken(_ token: String?) {
        guard let offlineStore else { return }
        guard let token else {
            offlineStore.remove(key: CacheKeys.tasksSync)
            return
        }
        offlineStore.set(key: CacheKeys.tasksSync, entityType: "taskSync", value: token, lastSyncAt: nil)
    }

    func refreshAfterSync() async {
        // Queue replay now reconciles item-level deltas directly into the store.
    }

    private func persistCurrentSnapshot() {
        guard selection != .none else { return }
        let scopeValue = currentScope ?? selection.scope ?? selection.cacheKey
        let snapshot = TaskListResponse(
            scope: scopeValue,
            generatedAt: nil,
            tasks: tasks,
            projects: projects,
            groups: groups
        )
        let cacheKey = CacheKeys.tasksList(selectionKey: selection.cacheKey)
        cache.set(key: cacheKey, value: snapshot, ttlSeconds: CachePolicy.tasksList)
        offlineStore?.set(key: cacheKey, entityType: "taskList", value: snapshot, lastSyncAt: nil)
    }

    private func applyServerTasks(_ incomingTasks: [TaskItem]) {
        guard !incomingTasks.isEmpty else { return }
        for task in incomingTasks {
            pendingRemovals.remove(task.id)
            if shouldDisplay(task, in: selection) {
                upsertVisibleTask(task)
            } else {
                tasks.removeAll { $0.id == task.id }
            }
        }
    }

    private func mergeProjects(_ incomingProjects: [TaskProject]) {
        guard !incomingProjects.isEmpty else { return }
        var updatedProjects = projects
        for project in incomingProjects {
            if let index = updatedProjects.firstIndex(where: { $0.id == project.id }) {
                updatedProjects[index] = project
            } else {
                updatedProjects.append(project)
            }
        }
        projects = updatedProjects
    }

    private func mergeGroups(_ incomingGroups: [TaskGroup]) {
        guard !incomingGroups.isEmpty else { return }
        var updatedGroups = groups
        for group in incomingGroups {
            if let index = updatedGroups.firstIndex(where: { $0.id == group.id }) {
                updatedGroups[index] = group
            } else {
                updatedGroups.append(group)
            }
        }
        groups = updatedGroups
    }

    private func updateTask(id: String, update: (TaskItem) -> TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index] = update(tasks[index])
    }

    private func addLocalTask(operation: TaskOperationPayload, title: String) {
        let placeholderId = "local-\(UUID().uuidString)"
        registerPendingTask(operationId: operation.operationId, placeholderId: placeholderId)
        let task = TaskItem(
            id: placeholderId,
            title: title,
            status: "open",
            deadline: operation.dueDate,
            notes: operation.notes,
            projectId: operation.listId,
            groupId: nil,
            repeating: operation.recurrenceRule != nil,
            repeatTemplate: nil,
            recurrenceRule: operation.recurrenceRule,
            nextInstanceDate: nil,
            updatedAt: nil,
            deletedAt: nil,
            isPreview: true
        )
        tasks.insert(task, at: 0)
    }

    private func updatedTask(
        _ task: TaskItem,
        title: String? = nil,
        notes: String? = nil,
        projectId: String? = nil,
        deadline: String? = nil,
        recurrenceRule: RecurrenceRule? = nil,
        repeating: Bool? = nil
    ) -> TaskItem {
        TaskItem(
            id: task.id,
            title: title ?? task.title,
            status: task.status,
            deadline: deadline ?? task.deadline,
            notes: notes ?? task.notes,
            projectId: projectId ?? task.projectId,
            groupId: task.groupId,
            repeating: repeating ?? task.repeating,
            repeatTemplate: task.repeatTemplate,
            recurrenceRule: recurrenceRule ?? task.recurrenceRule,
            nextInstanceDate: task.nextInstanceDate,
            updatedAt: task.updatedAt,
            deletedAt: task.deletedAt,
            isPreview: task.isPreview
        )
    }

    private func registerPendingTask(operationId: String, placeholderId: String) {
        guard let offlineStore else { return }
        let key = pendingTaskKey(operationId: operationId)
        offlineStore.set(key: key, entityType: "taskPending", value: placeholderId, lastSyncAt: nil)
    }

    private func removePendingTaskRegistration(operationId: String) {
        guard let offlineStore else { return }
        offlineStore.remove(key: pendingTaskKey(operationId: operationId))
    }

    private func pendingTaskKey(operationId: String) -> String {
        "tasks.pending.\(operationId)"
    }

    private func localOperation(from op: String) -> LocalTaskOperation? {
        switch op.lowercased() {
        case "add":
            return .add
        case "complete", "trash":
            return .remove
        case "rename":
            return .rename
        case "notes":
            return .notes
        case "move":
            return .move
        case "set_due", "defer":
            return .setDue
        case "clear_due":
            return .clearDue
        case "set_repeat":
            return .setRepeat
        default:
            return nil
        }
    }

    private func applyLocalOperation(_ operation: TaskOperationPayload, kind: LocalTaskOperation) {
        switch kind {
        case .add:
            guard let title = operation.title else { return }
            addLocalTask(operation: operation, title: title)
        case .remove:
            guard let taskId = operation.id else { return }
            _ = removeTask(id: taskId)
        case .rename:
            updateOperationTask(operation) { task in
                updatedTask(task, title: operation.title)
            }
        case .notes:
            updateOperationTask(operation) { task in
                updatedTask(task, notes: operation.notes)
            }
        case .move:
            updateOperationTask(operation) { task in
                updatedTask(task, projectId: operation.listId)
            }
        case .setDue:
            updateOperationTask(operation) { task in
                updatedTask(task, deadline: operation.dueDate)
            }
        case .clearDue:
            updateOperationTask(operation) { task in
                updatedTask(task, deadline: nil)
            }
        case .setRepeat:
            updateOperationTask(operation) { task in
                updatedTask(
                    task,
                    recurrenceRule: operation.recurrenceRule,
                    repeating: operation.recurrenceRule != nil
                )
            }
        }
    }

    private func updateOperationTask(
        _ operation: TaskOperationPayload,
        update: (TaskItem) -> TaskItem
    ) {
        guard let taskId = operation.id else { return }
        updateTask(id: taskId, update: update)
    }

    private func reconcileVisibilityAfterLocalOperation(
        _ operation: TaskOperationPayload,
        kind: LocalTaskOperation
    ) {
        guard let taskId = operation.id else { return }
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }

        switch kind {
        case .rename, .notes:
            guard case .search = selection else { return }
        case .setDue, .clearDue:
            switch selection {
            case .today, .upcoming:
                break
            default:
                return
            }
        case .add, .remove, .move, .setRepeat:
            return
        }

        if !shouldDisplay(task, in: selection) {
            tasks.removeAll { $0.id == taskId }
        }
    }

    private func shouldDisplay(_ task: TaskItem, in selection: TaskSelection) -> Bool {
        if task.isPreview {
            return true
        }
        if task.deletedAt != nil {
            return false
        }

        switch selection {
        case .none:
            return false
        case .today, .upcoming:
            return shouldDisplayScheduledTask(task, in: selection)
        case .completed:
            return task.status == "completed"
        case .project(let id):
            return task.projectId == id && task.status != "completed" && task.status != "trashed"
        case .group(let id):
            return task.groupId == id && task.status != "completed" && task.status != "trashed"
        case .search(let query):
            let haystack = [task.title, task.notes ?? ""].joined(separator: "\n")
            return task.status != "completed"
                && task.status != "trashed"
                && haystack.localizedCaseInsensitiveContains(query)
        }
    }

    private func shouldDisplayScheduledTask(_ task: TaskItem, in selection: TaskSelection) -> Bool {
        guard task.status != "completed", task.status != "trashed", task.status != "someday" else {
            return false
        }
        guard
            let dateKey = task.deadline.map({ String($0.prefix(10)) }),
            let deadline = TasksUtils.tasksDateFormatter.date(from: dateKey)
        else {
            return false
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        switch selection {
        case .today:
            return deadline <= startOfDay
        case .upcoming:
            return deadline > startOfDay
        default:
            return false
        }
    }

    private func upsertVisibleTask(_ task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
    }
}

enum LocalTaskOperation {
    case add
    case remove
    case rename
    case notes
    case move
    case setDue
    case clearDue
    case setRepeat
}

extension TaskSelection {
    var isSearch: Bool { if case .search = self { true } else { false } }
}
