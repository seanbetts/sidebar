import Foundation
import Combine

// MARK: - TasksStore

@MainActor
public final class TasksStore: ObservableObject {
    @Published public private(set) var selection: TaskSelection = .today
    @Published public private(set) var tasks: [TaskItem] = []
    @Published public private(set) var groups: [TaskGroup] = []
    @Published public private(set) var projects: [TaskProject] = []
    @Published public private(set) var counts: TaskCountsResponse?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var searchPending: Bool = false
    @Published public private(set) var errorMessage: String?

    private let api: any TasksProviding
    private let cache: CacheClient
    private var pendingRemovals: Set<String> = []

    public init(api: any TasksProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func load(selection: TaskSelection, force: Bool = false) async {
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
        await refreshCounts()
    }

    public func reset() {
        selection = .today
        tasks = []
        groups = []
        projects = []
        counts = nil
        isLoading = false
        searchPending = false
        errorMessage = nil
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

    /// Clears a task from pending removals (called when server confirms removal).
    public func confirmRemoval(id: String) {
        pendingRemovals.remove(id)
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
        } catch {
            // Ignore counts refresh failures; keep last known counts.
        }
    }

    private func fetch(selection: TaskSelection) async throws -> TaskListResponse {
        switch selection {
        case .search(let query):
            return try await api.search(query: query)
        case .group(let id):
            return try await api.groupTasks(groupId: id)
        case .project(let id):
            return try await api.projectTasks(projectId: id)
        case .inbox, .today, .upcoming:
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
        if persist {
            let cacheKey = CacheKeys.tasksList(selectionKey: selection.cacheKey)
            cache.set(key: cacheKey, value: list, ttlSeconds: CachePolicy.tasksList)
        }
    }

    private func finishLoading(isSearch: Bool) {
        if isSearch {
            searchPending = false
        } else {
            isLoading = false
        }
    }
}

extension TaskSelection {
    var isSearch: Bool {
        if case .search = self {
            return true
        }
        return false
    }
}
