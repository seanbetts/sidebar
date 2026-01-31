import Foundation
import sideBarShared
import Combine

// MARK: - TasksStore

@MainActor
public final class TasksStore: ObservableObject {
    @Published public private(set) var selection: TaskSelection = .none
    @Published public private(set) var tasks: [TaskItem] = []
    @Published public private(set) var groups: [TaskGroup] = []
    @Published public private(set) var projects: [TaskProject] = []
    @Published public private(set) var counts: TaskCountsResponse?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var searchPending: Bool = false
    @Published public private(set) var errorMessage: String?

    private let api: any TasksProviding
    private let cache: CacheClient
    private let offlineStore: OfflineStore?
    private let networkStatus: (any NetworkStatusProviding)?
    private var pendingRemovals: Set<String> = []
    private var currentScope: String?
    weak var writeQueue: WriteQueue?

    public init(
        api: any TasksProviding,
        cache: CacheClient,
        offlineStore: OfflineStore? = nil,
        networkStatus: (any NetworkStatusProviding)? = nil
    ) {
        self.api = api
        self.cache = cache
        self.offlineStore = offlineStore
        self.networkStatus = networkStatus
    }

    public func attachWriteQueue(_ writeQueue: WriteQueue) {
        self.writeQueue = writeQueue
    }

    public func load(selection: TaskSelection, force: Bool = false) async {
        if selection == .none {
            self.selection = selection
            errorMessage = nil
            let fallbackSelection: TaskSelection = .today
            let cacheKey = CacheKeys.tasksList(selectionKey: fallbackSelection.cacheKey)
            if let cached: TaskListResponse = cache.get(key: cacheKey) {
                apply(list: cached, persist: false)
                Task { [weak self] in
                    await self?.refresh(selection: fallbackSelection)
                }
                return
            }
            if !force, let offline = offlineSnapshot(for: fallbackSelection) {
                apply(list: offline, persist: false)
                if networkStatus?.isNetworkAvailable ?? true {
                    Task { [weak self] in
                        await self?.refresh(selection: fallbackSelection)
                    }
                }
                return
            }
            Task { [weak self] in
                await self?.refresh(selection: fallbackSelection)
            }
            return
        }
        let cacheKey = CacheKeys.tasksList(selectionKey: selection.cacheKey)
        let cached: TaskListResponse? = cache.get(key: cacheKey)
        self.selection = selection
        errorMessage = nil
        if selection.isSearch {
            if tasks.isEmpty {
                searchPending = true
            }
        } else if cached == nil {
            isLoading = true
            tasks = []
        }
        if let cached {
            apply(list: cached, persist: false)
            Task { [weak self] in
                await self?.refresh(selection: selection)
            }
            finishLoading(isSearch: selection.isSearch)
            return
        }
        if !force, let offline = offlineSnapshot(for: selection) {
            apply(list: offline, persist: false)
            if networkStatus?.isNetworkAvailable ?? true {
                Task { [weak self] in
                    await self?.refresh(selection: selection)
                }
            }
            finishLoading(isSearch: selection.isSearch)
            return
        }
        await refresh(selection: selection)
        finishLoading(isSearch: selection.isSearch)
    }

    public func loadCounts(force: Bool = false) async {
        errorMessage = nil
        if let cached: TaskCountsResponse = cache.get(key: CacheKeys.tasksCounts) {
            counts = cached
            Task { [weak self] in
                await self?.refreshCounts()
            }
            return
        }
        if !force, let offline = offlineStore?.get(key: CacheKeys.tasksCounts, as: TaskCountsResponse.self) {
            counts = offline
            if networkStatus?.isNetworkAvailable ?? true {
                Task { [weak self] in
                    await self?.refreshCounts()
                }
            }
            return
        }
        await refreshCounts()
    }

    public func reset() {
        selection = .none
        tasks = []
        groups = []
        projects = []
        counts = nil
        isLoading = false
        searchPending = false
        errorMessage = nil
    }

    /// Decrements today count optimistically for offline operations
    public func decrementTodayCount() {
        guard let currentCounts = counts else { return }
        let newToday = max(0, currentCounts.counts.today - 1)
        counts = TaskCountsResponse(
            generatedAt: currentCounts.generatedAt,
            counts: TaskCounts(
                inbox: currentCounts.counts.inbox,
                today: newToday,
                upcoming: currentCounts.counts.upcoming,
                completed: currentCounts.counts.completed
            ),
            projects: currentCounts.projects,
            groups: currentCounts.groups
        )
    }

    /// Increments today count optimistically for offline operations
    public func incrementTodayCount() {
        guard let currentCounts = counts else { return }
        counts = TaskCountsResponse(
            generatedAt: currentCounts.generatedAt,
            counts: TaskCounts(
                inbox: currentCounts.counts.inbox,
                today: currentCounts.counts.today + 1,
                upcoming: currentCounts.counts.upcoming,
                completed: currentCounts.counts.completed
            ),
            projects: currentCounts.projects,
            groups: currentCounts.groups
        )
    }

    /// Optimistically removes a task from the local list. Returns the task for restoration if needed.
    public func removeTask(id: String) -> TaskItem? {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let task = tasks[index]
        tasks.remove(at: index)
        pendingRemovals.insert(id)
        return task
    }

    /// Restores a previously removed task (used when an optimistic update fails).
    public func restoreTask(_ task: TaskItem) {
        pendingRemovals.remove(task.id)
        tasks.insert(task, at: 0)
    }

    private func refresh(selection: TaskSelection) async {
        do {
            let response = try await fetch(selection: selection)
            apply(list: response, persist: true)
        } catch {
            if tasks.isEmpty {
                errorMessage = ErrorMapping.message(for: error)
            }
        }
    }

    private func refreshCounts() async {
        do {
            let response = try await api.counts()
            counts = response
            cache.set(key: CacheKeys.tasksCounts, value: response, ttlSeconds: CachePolicy.tasksCounts)
            offlineStore?.set(
                key: CacheKeys.tasksCounts,
                entityType: "taskCounts",
                value: response,
                lastSyncAt: nil
            )
        } catch {
            // Ignore counts refresh failures; keep last known counts.
        }
    }

    private func fetch(selection: TaskSelection) async throws -> TaskListResponse {
        switch selection {
        case .none:
            throw APIClientError.invalidUrl
        case .search(let query):
            return try await api.search(query: query)
        case .group(let id):
            return try await api.groupTasks(groupId: id)
        case .project(let id):
            return try await api.projectTasks(projectId: id)
        case .inbox, .today, .upcoming, .completed:
            guard let scope = selection.scope else {
                throw APIClientError.invalidUrl
            }
            return try await api.list(scope: scope)
        }
    }

    private func apply(list: TaskListResponse, persist: Bool) {
        // Filter out tasks that are pending removal (optimistic updates)
        tasks = list.tasks.filter { !pendingRemovals.contains($0.id) }
        groups = list.groups ?? []
        projects = list.projects ?? []
        currentScope = list.scope

        // Clean up pendingRemovals: remove IDs that are no longer in the server response
        // (confirms the server has processed the removal)
        if persist {
            let serverTaskIds = Set(list.tasks.map { $0.id })
            pendingRemovals = pendingRemovals.filter { serverTaskIds.contains($0) }

            let cacheKey = CacheKeys.tasksList(selectionKey: selection.cacheKey)
            cache.set(key: cacheKey, value: list, ttlSeconds: CachePolicy.tasksList)
            offlineStore?.set(
                key: cacheKey,
                entityType: "taskList",
                value: list,
                lastSyncAt: nil
            )
        }
    }

    private func finishLoading(isSearch: Bool) {
        if isSearch {
            searchPending = false
        } else {
            isLoading = false
        }
    }

    private func offlineSnapshot(for selection: TaskSelection) -> TaskListResponse? {
        guard let offlineStore else { return nil }
        let cacheKey = CacheKeys.tasksList(selectionKey: selection.cacheKey)
        return offlineStore.get(key: cacheKey, as: TaskListResponse.self)
    }
}

extension TasksStore {
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

    func applyLocalOperation(_ operation: TaskOperationPayload) {
        guard let kind = localOperation(from: operation.op) else { return }
        applyLocalOperation(operation, kind: kind)
        persistCurrentSnapshot()
    }

    func removePendingTaskPlaceholder(operationId: String) {
        guard let offlineStore else { return }
        let key = pendingTaskKey(operationId: operationId)
        guard let placeholderId = offlineStore.get(key: key, as: String.self) else { return }
        tasks.removeAll { $0.id == placeholderId }
        offlineStore.remove(key: key)
        persistCurrentSnapshot()
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
        guard selection != .none else {
            return
        }
        await load(selection: selection, force: true)
        await loadCounts(force: true)
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
}

private enum LocalTaskOperation {
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
    var isSearch: Bool {
        if case .search = self {
            return true
        }
        return false
    }
}
