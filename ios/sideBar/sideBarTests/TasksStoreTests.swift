import Foundation
import XCTest
@testable import sideBar

@MainActor
final class TasksStoreTests: XCTestCase {
    func testLoadUsesOfflineSnapshotWhenOffline() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let networkStatus = TestNetworkStatus(isNetworkAvailable: false)
        let store = TasksStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: networkStatus
        )

        let selection: TaskSelection = .today
        let task = TaskItem(id: "task-1", title: "Offline", status: "open")
        let list = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [task],
            projects: nil,
            groups: nil
        )
        offlineStore.set(
            key: CacheKeys.tasksList(selectionKey: selection.cacheKey),
            entityType: "taskList",
            value: list,
            lastSyncAt: nil
        )

        await store.load(selection: selection)

        XCTAssertEqual(store.tasks, [task])
        XCTAssertEqual(api.listCallCount, 0)
    }

    func testApplyLocalAddCreatesPreviewTask() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let operationId = UUID().uuidString
        let operation = TaskOperationPayload(
            operationId: operationId,
            op: "add",
            id: nil,
            title: "Queued Task",
            notes: "Offline",
            listId: nil,
            dueDate: nil,
            startDate: nil,
            recurrenceRule: nil,
            clientUpdatedAt: nil
        )

        store.applyLocalOperation(operation)

        XCTAssertEqual(store.tasks.first?.title, "Queued Task")
        XCTAssertEqual(store.tasks.first?.notes, "Offline")
        XCTAssertEqual(store.tasks.first?.isPreview, true)
        let pendingKey = "tasks.pending.\(operationId)"
        let placeholderId = offlineStore.get(key: pendingKey, as: String.self)
        XCTAssertEqual(store.tasks.first?.id, placeholderId)
    }

    func testLoadCountsUsesCacheWhenNotForcedAndRefreshesInBackground() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let cachedCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(inbox: 1, today: 7, upcoming: 2, completed: 3),
            projects: [],
            groups: []
        )
        cache.set(key: CacheKeys.tasksCounts, value: cachedCounts, ttlSeconds: 60)

        let refreshedCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(inbox: 1, today: 5, upcoming: 2, completed: 3),
            projects: [],
            groups: []
        )
        api.countsResponse = refreshedCounts

        await store.loadCounts()

        XCTAssertEqual(store.counts?.counts.today, 7)
        XCTAssertEqual(api.countsCallCount, 0)

        // Background refresh is asynchronous after returning cached value.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(api.countsCallCount, 1)
    }

    func testLoadCountsForceBypassesCacheAndFetchesImmediately() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let cachedCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(inbox: 1, today: 7, upcoming: 2, completed: 3),
            projects: [],
            groups: []
        )
        cache.set(key: CacheKeys.tasksCounts, value: cachedCounts, ttlSeconds: 60)

        let refreshedCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(inbox: 1, today: 4, upcoming: 2, completed: 3),
            projects: [],
            groups: []
        )
        api.countsResponse = refreshedCounts

        await store.loadCounts(force: true)

        XCTAssertEqual(api.countsCallCount, 1)
        XCTAssertEqual(store.counts?.counts.today, 4)
    }

    func testLoadNoneDoesNotFetchFallbackList() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        await store.load(selection: .none)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.selection, .none)
        XCTAssertEqual(store.tasks, [])
        XCTAssertEqual(api.listCallCount, 0)
    }

    func testCachedListRefreshDoesNotOverrideNewerSelection() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let cachedTodayTask = TaskItem(id: "today-cached", title: "Cached today", status: "open")
        let cachedToday = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [cachedTodayTask],
            projects: nil,
            groups: nil
        )
        cache.set(
            key: CacheKeys.tasksList(selectionKey: TaskSelection.today.cacheKey),
            value: cachedToday,
            ttlSeconds: 60
        )

        let refreshedTodayTask = TaskItem(id: "today-fresh", title: "Fresh today", status: "open")
        api.listResponsesByScope["today"] = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [refreshedTodayTask],
            projects: nil,
            groups: nil
        )
        api.listResponseDelaysByScope["today"] = 200_000_000

        let upcomingTask = TaskItem(id: "upcoming", title: "Upcoming", status: "open")
        api.listResponsesByScope["upcoming"] = TaskListResponse(
            scope: "upcoming",
            generatedAt: nil,
            tasks: [upcomingTask],
            projects: nil,
            groups: nil
        )

        await store.load(selection: .today)
        XCTAssertEqual(store.selection, .today)
        XCTAssertEqual(store.tasks, [cachedTodayTask])

        await store.load(selection: .upcoming, force: true)
        XCTAssertEqual(store.selection, .upcoming)
        XCTAssertEqual(store.tasks, [upcomingTask])

        try? await Task.sleep(nanoseconds: 260_000_000)
        XCTAssertEqual(store.selection, .upcoming)
        XCTAssertEqual(store.tasks, [upcomingTask])
    }

    func testCachedListRefreshesCoalesceWhenAlreadyInFlight() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let cachedToday = TaskListResponse(scope: "today", generatedAt: nil, tasks: [], projects: nil, groups: nil)
        cache.set(
            key: CacheKeys.tasksList(selectionKey: TaskSelection.today.cacheKey),
            value: cachedToday,
            ttlSeconds: 60
        )
        api.listResponseDelaysByScope["today"] = 200_000_000

        await store.load(selection: .today)
        await store.load(selection: .today)
        try? await Task.sleep(nanoseconds: 260_000_000)

        XCTAssertEqual(api.listCallCount, 1)
    }

    func testCachedCountRefreshesCoalesceWhenAlreadyInFlight() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let cachedCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(inbox: 1, today: 7, upcoming: 2, completed: 3),
            projects: [],
            groups: []
        )
        cache.set(key: CacheKeys.tasksCounts, value: cachedCounts, ttlSeconds: 60)
        api.countsResponseDelayNanoseconds = 200_000_000

        await store.loadCounts()
        await store.loadCounts()
        try? await Task.sleep(nanoseconds: 260_000_000)

        XCTAssertEqual(api.countsCallCount, 1)
    }
}

@MainActor
private final class TestNetworkStatus: NetworkStatusProviding {
    var isNetworkAvailable: Bool
    var isOffline: Bool

    init(isNetworkAvailable: Bool, isOffline: Bool = false) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isOffline = isOffline
    }
}

private final class StubTasksAPI: TasksProviding {
    var listCallCount: Int = 0
    var countsCallCount: Int = 0
    var listResponsesByScope: [String: TaskListResponse] = [:]
    var listResponseDelaysByScope: [String: UInt64] = [:]
    var countsResponseDelayNanoseconds: UInt64 = 0
    var countsResponse = TaskCountsResponse(
        generatedAt: nil,
        counts: TaskCounts(inbox: 0, today: 0, upcoming: 0, completed: 0),
        projects: [],
        groups: []
    )

    func list(scope: String) async throws -> TaskListResponse {
        listCallCount += 1
        if let delay = listResponseDelaysByScope[scope], delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return listResponsesByScope[scope]
            ?? TaskListResponse(scope: scope, generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }

    func projectTasks(projectId: String) async throws -> TaskListResponse {
        throw StubError.unused
    }

    func groupTasks(groupId: String) async throws -> TaskListResponse {
        throw StubError.unused
    }

    func search(query: String) async throws -> TaskListResponse {
        throw StubError.unused
    }

    func counts() async throws -> TaskCountsResponse {
        countsCallCount += 1
        if countsResponseDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: countsResponseDelayNanoseconds)
        }
        return countsResponse
    }

    func createGroup(title: String) async throws -> TaskGroup {
        throw StubError.unused
    }

    func renameGroup(groupId: String, title: String) async throws -> TaskGroup {
        throw StubError.unused
    }

    func deleteGroup(groupId: String) async throws {
        throw StubError.unused
    }

    func createProject(title: String, groupId: String?) async throws -> TaskProject {
        throw StubError.unused
    }

    func renameProject(projectId: String, title: String) async throws -> TaskProject {
        throw StubError.unused
    }

    func deleteProject(projectId: String) async throws {
        throw StubError.unused
    }

    func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse {
        throw StubError.unused
    }

    func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse {
        throw StubError.unused
    }
}

private enum StubError: Error {
    case unused
}
