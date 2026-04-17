import Foundation

extension TasksStore {
    func pendingTaskWrites() async -> [PendingWriteSummary] {
        guard let writeQueue else { return [] }
        return (try? await writeQueue.fetchPendingWrites()) ?? []
    }

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

    func pendingPlaceholderId(operationId: String) -> String? {
        guard let offlineStore else { return nil }
        if let placeholder = offlineStore.get(key: pendingTaskKey(operationId: operationId), as: String.self) {
            return placeholder
        }
        if let placeholder = offlineStore.get(key: pendingGroupKey(operationId: operationId), as: String.self) {
            return placeholder
        }
        return offlineStore.get(key: pendingProjectKey(operationId: operationId), as: String.self)
    }

    func remapPendingTaskReferences(localID: String, serverID: String) async {
        do {
            try await writeQueue?.applyServerIdentityMap(
                entityType: .task,
                localID: localID,
                serverID: serverID
            )
        } catch {
            // Best-effort remap for downstream queued mutations.
        }
    }

    func removePendingTaskPlaceholder(operationId: String) {
        guard let offlineStore else { return }
        if let placeholderId = offlineStore.get(key: pendingTaskKey(operationId: operationId), as: String.self) {
            tasks.removeAll { $0.id == placeholderId }
            offlineStore.remove(key: pendingTaskKey(operationId: operationId))
            return
        }
        if let placeholderId = offlineStore.get(key: pendingGroupKey(operationId: operationId), as: String.self) {
            groups.removeAll { $0.id == placeholderId }
            offlineStore.remove(key: pendingGroupKey(operationId: operationId))
            return
        }
        if let placeholderId = offlineStore.get(key: pendingProjectKey(operationId: operationId), as: String.self) {
            projects.removeAll { $0.id == placeholderId }
            offlineStore.remove(key: pendingProjectKey(operationId: operationId))
        }
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
            if project.deletedAt != nil {
                updatedProjects.removeAll { $0.id == project.id }
            } else if let index = updatedProjects.firstIndex(where: { $0.id == project.id }) {
                updatedProjects[index] = project
            } else {
                updatedProjects.append(project)
            }
        }
        projects = updatedProjects
    }

    func mergedVisibleTasks(
        remote: [TaskItem],
        pendingWrites: [PendingWriteSummary]
    ) -> [TaskItem] {
        let filteredRemote = remote.filter { !pendingRemovals.contains($0.id) }
        let protectedTaskIDs = Set(
            pendingWrites.compactMap { write -> String? in
                guard write.entityType == WriteEntityType.task.rawValue,
                      let entityId = write.entityId,
                      !isPendingGroupOperation(write.operationType),
                      !isPendingProjectOperation(write.operationType) else {
                    return nil
                }
                return entityId
            }
        )
        let localTasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let mergedRemote = filteredRemote.map { task in
            if protectedTaskIDs.contains(task.id), let local = localTasksByID[task.id] {
                return local
            }
            return task
        }

        let previewTasks = tasks.filter(\.isPreview)
        guard !previewTasks.isEmpty else {
            return mergedRemote
        }
        let previewIDs = Set(previewTasks.map(\.id))
        return previewTasks + mergedRemote.filter { !previewIDs.contains($0.id) }
    }

    func mergedVisibleGroups(
        remote: [TaskGroup],
        pendingWrites: [PendingWriteSummary]
    ) -> [TaskGroup] {
        let protectedGroupIDs = Set(
            pendingWrites.compactMap { write -> String? in
                guard let entityId = write.entityId,
                      isPendingGroupOperation(write.operationType) else {
                    return nil
                }
                return entityId
            }
        )
        let localGroupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        let mergedRemote = remote.map { group in
            if protectedGroupIDs.contains(group.id), let local = localGroupsByID[group.id] {
                return local
            }
            return group
        }

        let localPreviewGroups = groups.filter { $0.id.hasPrefix("local-group-") }
        guard !localPreviewGroups.isEmpty else {
            return mergedRemote
        }
        let previewIDs = Set(localPreviewGroups.map(\.id))
        return localPreviewGroups + mergedRemote.filter { !previewIDs.contains($0.id) }
    }

    func mergedVisibleProjects(
        remote: [TaskProject],
        pendingWrites: [PendingWriteSummary]
    ) -> [TaskProject] {
        let protectedProjectIDs = Set(
            pendingWrites.compactMap { write -> String? in
                guard let entityId = write.entityId,
                      isPendingProjectOperation(write.operationType) else {
                    return nil
                }
                return entityId
            }
        )
        let localProjectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let mergedRemote = remote.map { project in
            if protectedProjectIDs.contains(project.id), let local = localProjectsByID[project.id] {
                return local
            }
            return project
        }

        let localPreviewProjects = projects.filter { $0.id.hasPrefix("local-project-") }
        guard !localPreviewProjects.isEmpty else {
            return mergedRemote
        }
        let previewIDs = Set(localPreviewProjects.map(\.id))
        return localPreviewProjects + mergedRemote.filter { !previewIDs.contains($0.id) }
    }

    func isPendingGroupOperation(_ operationType: String) -> Bool {
        operationType == LocalTaskOperation.createGroup.rawValue
            || operationType == LocalTaskOperation.renameGroup.rawValue
            || operationType == LocalTaskOperation.deleteGroup.rawValue
    }

    func isPendingProjectOperation(_ operationType: String) -> Bool {
        operationType == LocalTaskOperation.createProject.rawValue
            || operationType == LocalTaskOperation.renameProject.rawValue
            || operationType == LocalTaskOperation.deleteProject.rawValue
    }

    private func mergeGroups(_ incomingGroups: [TaskGroup]) {
        guard !incomingGroups.isEmpty else { return }
        var updatedGroups = groups
        for group in incomingGroups {
            if group.deletedAt != nil {
                updatedGroups.removeAll { $0.id == group.id }
            } else if let index = updatedGroups.firstIndex(where: { $0.id == group.id }) {
                updatedGroups[index] = group
            } else {
                updatedGroups.append(group)
            }
        }
        groups = updatedGroups
    }

    func updateTask(id: String, update: (TaskItem) -> TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index] = update(tasks[index])
    }

    func addLocalTask(operation: TaskOperationPayload, title: String) {
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

    func updatedTask(
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
}
