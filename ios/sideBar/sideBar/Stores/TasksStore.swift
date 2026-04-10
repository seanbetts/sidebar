import Foundation
import sideBarShared
import Combine
// MARK: - TasksStore
/// Persistent store for task items, groups, and projects with optimistic update support.
@MainActor public final class TasksStore: ObservableObject {
    @Published public private(set) var selection: TaskSelection = .none
    @Published public internal(set) var tasks: [TaskItem] = []
    @Published public internal(set) var groups: [TaskGroup] = []
    @Published public internal(set) var projects: [TaskProject] = []
    @Published public internal(set) var counts: TaskCountsResponse?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var searchPending: Bool = false
    @Published public private(set) var errorMessage: String?

    private let api: any TasksProviding
    let cache: CacheClient
    let offlineStore: OfflineStore?
    private let networkStatus: (any NetworkStatusProviding)?
    var pendingRemovals: Set<String> = []
    var currentScope: String?
    private var latestLoadRequestId: UInt64 = 0
    private var inFlightListRefreshes: [TaskSelection: Task<TaskListResponse, Error>] = [:]
    private var inFlightCountsRefresh: Task<TaskCountsResponse, Error>?
    weak var spotlightIndexer: (any SpotlightIndexing)?
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
        let requestId = beginLoadRequest()
        if selection == .none {
            self.selection = selection
            errorMessage = nil
            isLoading = false
            searchPending = false
            tasks = []
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
        if applyCachedOrOffline(
            force: force,
            cacheKey: cacheKey,
            type: TaskListResponse.self,
            apply: { [weak self] list in
                self?.apply(list: list, selection: selection, persist: false)
            },
            refreshIfAvailable: { [weak self] in
                guard let self else { return }
                await self.refresh(selection: selection, requestId: requestId)
            }
        ) {
            finishLoading(isSearch: selection.isSearch)
            return
        }
        await refresh(selection: selection, requestId: requestId)
        finishLoading(isSearch: selection.isSearch)
    }
    public func loadCounts(force: Bool = false) async {
        errorMessage = nil
        if applyCachedOrOffline(
            force: force,
            cacheKey: CacheKeys.tasksCounts,
            type: TaskCountsResponse.self,
            apply: { [weak self] response in
                self?.counts = response
            },
            refreshIfAvailable: { [weak self] in
                guard let self else { return }
                await self.refreshCounts()
            }
        ) {
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

    private func refresh(selection: TaskSelection, requestId: UInt64?) async {
        do {
            let response = try await fetchWithDedupe(selection: selection)
            let shouldApplyVisibleState = shouldApplyVisibleState(
                for: selection,
                requestId: requestId
            )
            apply(
                list: response,
                selection: selection,
                persist: true,
                updateVisibleState: shouldApplyVisibleState
            )
        } catch {
            if shouldApplyVisibleState(for: selection, requestId: requestId), tasks.isEmpty {
                errorMessage = ErrorMapping.message(for: error)
            }
        }
    }

    private func refreshCounts() async {
        do {
            let response = try await fetchCountsWithDedupe()
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
        case .today, .upcoming, .completed:
            guard let scope = selection.scope else {
                throw APIClientError.invalidUrl
            }
            return try await api.list(scope: scope)
        }
    }

    private func apply(
        list: TaskListResponse,
        selection: TaskSelection,
        persist: Bool,
        updateVisibleState: Bool = true
    ) {
        if updateVisibleState {
            // Filter out tasks that are pending removal (optimistic updates)
            let incomingTasks = list.tasks.filter { !pendingRemovals.contains($0.id) }
            if tasks != incomingTasks {
                tasks = incomingTasks
            }
            if let responseGroups = list.groups {
                if groups != responseGroups {
                    groups = responseGroups
                }
            }
            if let responseProjects = list.projects {
                if projects != responseProjects {
                    projects = responseProjects
                }
            }
            currentScope = list.scope
        }

        if persist {
            if updateVisibleState {
                // Clean up pendingRemovals: remove IDs that are no longer in the server response
                // (confirms the server has processed the removal)
                let serverTaskIds = Set(list.tasks.map { $0.id })
                pendingRemovals = pendingRemovals.filter { serverTaskIds.contains($0) }
            }

            let cacheKey = CacheKeys.tasksList(selectionKey: selection.cacheKey)
            cache.set(key: cacheKey, value: list, ttlSeconds: CachePolicy.tasksList)
            offlineStore?.set(
                key: cacheKey,
                entityType: "taskList",
                value: list,
                lastSyncAt: nil
            )
            indexTasksInSpotlight(list.tasks)
        }
    }

    private func finishLoading(isSearch: Bool) {
        if isSearch {
            searchPending = false
        } else {
            isLoading = false
        }
    }

    private func beginLoadRequest() -> UInt64 {
        latestLoadRequestId &+= 1
        return latestLoadRequestId
    }

    private func shouldApplyVisibleState(
        for selection: TaskSelection,
        requestId: UInt64?
    ) -> Bool {
        if let requestId {
            return requestId == latestLoadRequestId && self.selection == selection
        }
        return self.selection == selection
    }

    private func fetchWithDedupe(selection: TaskSelection) async throws -> TaskListResponse {
        if let inFlight = inFlightListRefreshes[selection] {
            return try await inFlight.value
        }

        let task = Task<TaskListResponse, Error> {
            try await fetch(selection: selection)
        }
        inFlightListRefreshes[selection] = task
        defer { inFlightListRefreshes[selection] = nil }
        return try await task.value
    }

    private func fetchCountsWithDedupe() async throws -> TaskCountsResponse {
        if let inFlightCountsRefresh {
            return try await inFlightCountsRefresh.value
        }

        let task = Task<TaskCountsResponse, Error> {
            try await api.counts()
        }
        inFlightCountsRefresh = task
        defer { inFlightCountsRefresh = nil }
        return try await task.value
    }

    func canRefreshFromRemote() -> Bool {
        (networkStatus?.isNetworkAvailable ?? true) && (networkStatus?.isServerReachable ?? true)
    }

    func cachedSnapshot<T: Codable>(key: String) -> T? {
        cache.get(key: key)
    }

    func offlineSnapshot<T: Codable>(key: String, as type: T.Type) -> T? {
        offlineStore?.get(key: key, as: type)
    }

}
