import Foundation

extension TasksStore {
    func removePendingTaskRegistration(operationId: String) {
        guard let offlineStore else { return }
        offlineStore.remove(key: pendingTaskKey(operationId: operationId))
    }

    func pendingTaskKey(operationId: String) -> String {
        "tasks.pending.\(operationId)"
    }

    func pendingGroupKey(operationId: String) -> String {
        "tasks.pending.group.\(operationId)"
    }

    func pendingProjectKey(operationId: String) -> String {
        "tasks.pending.project.\(operationId)"
    }

    func localOperation(from op: String) -> LocalTaskOperation? {
        LocalTaskOperation(operationName: op)
    }

    func applyLocalOperation(_ operation: TaskOperationPayload, kind: LocalTaskOperation) {
        if applyGroupedLocalOperation(operation, kind: kind) {
            return
        }

        switch kind {
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
        case .reopen:
            updateOperationTask(operation) { task in
                updatedTask(task, status: "active")
            }
        case .add, .createGroup, .createProject, .renameGroup, .renameProject, .deleteGroup, .deleteProject, .remove:
            return
        }
    }

    func registerPendingTask(operationId: String, placeholderId: String) {
        guard let offlineStore else { return }
        offlineStore.set(
            key: pendingTaskKey(operationId: operationId),
            entityType: "taskPending",
            value: placeholderId,
            lastSyncAt: nil
        )
    }

    func registerPendingGroup(operationId: String, placeholderId: String) {
        guard let offlineStore else { return }
        offlineStore.set(
            key: pendingGroupKey(operationId: operationId),
            entityType: "taskGroupPending",
            value: placeholderId,
            lastSyncAt: nil
        )
    }

    func registerPendingProject(operationId: String, placeholderId: String) {
        guard let offlineStore else { return }
        offlineStore.set(
            key: pendingProjectKey(operationId: operationId),
            entityType: "taskProjectPending",
            value: placeholderId,
            lastSyncAt: nil
        )
    }

    func updateOperationTask(
        _ operation: TaskOperationPayload,
        update: (TaskItem) -> TaskItem
    ) {
        guard let taskId = operation.id else { return }
        updateTask(id: taskId, update: update)
    }

    func addLocalGroup(operation: TaskOperationPayload, title: String) {
        let placeholderId = "local-group-\(UUID().uuidString)"
        registerPendingGroup(operationId: operation.operationId, placeholderId: placeholderId)
        groups.insert(TaskGroup(id: placeholderId, title: title, updatedAt: nil), at: 0)
    }

    func addLocalProject(operation: TaskOperationPayload, title: String) {
        let placeholderId = "local-project-\(UUID().uuidString)"
        registerPendingProject(operationId: operation.operationId, placeholderId: placeholderId)
        projects.insert(
            TaskProject(
                id: placeholderId,
                title: title,
                groupId: operation.listId,
                status: "active",
                updatedAt: nil
            ),
            at: 0
        )
    }

    func updateGroup(id: String, update: (TaskGroup) -> TaskGroup) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index] = update(groups[index])
    }

    func updateProject(id: String, update: (TaskProject) -> TaskProject) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index] = update(projects[index])
    }

    func removeLocalGroup(id: String) {
        let relatedProjectIDs = Set(projects.filter { $0.groupId == id }.map(\.id))
        groups.removeAll { $0.id == id }
        projects.removeAll { $0.groupId == id }
        tasks.removeAll { task in
            task.groupId == id || (task.projectId.map { relatedProjectIDs.contains($0) } ?? false)
        }
    }

    func removeLocalProject(id: String) {
        projects.removeAll { $0.id == id }
        tasks.removeAll { $0.projectId == id }
    }

    func reconcileVisibilityAfterLocalOperation(
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
        case .reopen:
            break
        case .add, .createGroup, .renameGroup, .deleteGroup, .createProject, .renameProject, .deleteProject,
             .remove, .move, .setRepeat:
            return
        }

        if !shouldDisplay(task, in: selection) {
            tasks.removeAll { $0.id == taskId }
        }
    }

    func shouldDisplay(_ task: TaskItem, in selection: TaskSelection) -> Bool {
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

    func shouldDisplayScheduledTask(_ task: TaskItem, in selection: TaskSelection) -> Bool {
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

    func upsertVisibleTask(_ task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
    }

    private func applyLocalCreateOperation(_ operation: TaskOperationPayload, kind: LocalTaskOperation) {
        guard let title = operation.title else { return }
        switch kind {
        case .add:
            addLocalTask(operation: operation, title: title)
        case .createGroup:
            addLocalGroup(operation: operation, title: title)
        case .createProject:
            addLocalProject(operation: operation, title: title)
        default:
            return
        }
    }

    private func applyGroupedLocalOperation(
        _ operation: TaskOperationPayload,
        kind: LocalTaskOperation
    ) -> Bool {
        switch kind {
        case .add, .createGroup, .createProject:
            applyLocalCreateOperation(operation, kind: kind)
            return true
        case .renameGroup, .renameProject:
            applyLocalRenameOperation(operation, kind: kind)
            return true
        case .deleteGroup, .deleteProject:
            applyLocalDeleteOperation(operation, kind: kind)
            return true
        case .remove:
            guard let taskId = operation.id else { return true }
            _ = removeTask(id: taskId)
            return true
        default:
            return false
        }
    }

    private func applyLocalRenameOperation(_ operation: TaskOperationPayload, kind: LocalTaskOperation) {
        switch kind {
        case .renameGroup:
            guard let groupId = operation.id else { return }
            updateGroup(id: groupId) { group in
                TaskGroup(
                    id: group.id,
                    title: operation.title ?? group.title,
                    updatedAt: group.updatedAt,
                    deletedAt: group.deletedAt
                )
            }
        case .renameProject:
            guard let projectId = operation.id else { return }
            updateProject(id: projectId) { project in
                TaskProject(
                    id: project.id,
                    title: operation.title ?? project.title,
                    groupId: project.groupId,
                    status: project.status,
                    updatedAt: project.updatedAt,
                    deletedAt: project.deletedAt
                )
            }
        default:
            return
        }
    }

    private func applyLocalDeleteOperation(_ operation: TaskOperationPayload, kind: LocalTaskOperation) {
        guard let entityId = operation.id else { return }
        switch kind {
        case .deleteGroup:
            removeLocalGroup(id: entityId)
        case .deleteProject:
            removeLocalProject(id: entityId)
        default:
            return
        }
    }
}

enum LocalTaskOperation: String {
    case add = "add"
    case createGroup = "create_group"
    case renameGroup = "rename_group"
    case deleteGroup = "delete_group"
    case createProject = "create_project"
    case renameProject = "rename_project"
    case deleteProject = "delete_project"
    case remove = "remove"
    case rename = "rename"
    case notes = "notes"
    case move = "move"
    case setDue = "set_due"
    case clearDue = "clear_due"
    case setRepeat = "set_repeat"
    case reopen = "reopen"

    init?(operationName: String) {
        switch operationName.lowercased() {
        case "complete", "trash":
            self = .remove
        case "defer":
            self = .setDue
        default:
            self.init(rawValue: operationName.lowercased())
        }
    }
}

extension TaskSelection {
    var isSearch: Bool { if case .search = self { true } else { false } }
}
