import Foundation
import XCTest
@testable import sideBar

@MainActor
final class TasksStoreTests: XCTestCase {
    func testLoadUsesOfflineSnapshotWhenOffline() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let networkStatus = TasksStoreTestNetworkStatus(isNetworkAvailable: false)
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
        let api = TasksStoreStubTasksAPI()
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

    func testApplyLocalCreateGroupAddsGroup() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let operation = TaskOperationPayload(
            operationId: UUID().uuidString,
            op: "create_group",
            id: nil,
            title: "Work"
        )

        store.applyLocalOperation(operation)

        XCTAssertEqual(store.groups.map(\.title), ["Work"])
    }

    func testApplySyncResponseRemovesDeletedGroupsAndProjects() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        store.groups = [TaskGroup(id: "g1", title: "Work", updatedAt: nil)]
        store.projects = [TaskProject(id: "p1", title: "Launch", groupId: "g1", status: "active", updatedAt: nil)]

        let response = TaskSyncResponse(
            applied: ["op-1"],
            tasks: [],
            nextTasks: [],
            conflicts: [],
            updates: TaskSyncUpdates(
                tasks: [],
                projects: [
                    TaskProject(
                        id: "p1",
                        title: "Launch",
                        groupId: "g1",
                        status: "active",
                        updatedAt: "u1",
                        deletedAt: "2026-04-16T21:00:00Z"
                    )
                ],
                groups: [
                    TaskGroup(
                        id: "g1",
                        title: "Work",
                        updatedAt: "u1",
                        deletedAt: "2026-04-16T21:00:00Z"
                    )
                ]
            ),
            serverUpdatedSince: nil
        )

        store.applySyncResponse(response, operationId: "op-1")

        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertTrue(store.projects.isEmpty)
    }

    func testLoadCountsUsesCacheWhenNotForcedAndRefreshesInBackground() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let cachedCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 7, upcoming: 2, completed: 3),
            projects: [],
            groups: []
        )
        cache.set(key: CacheKeys.tasksCounts, value: cachedCounts, ttlSeconds: 60)

        let refreshedCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 5, upcoming: 2, completed: 3),
            projects: [],
            groups: []
        )
        api.countsResponse = refreshedCounts

        await store.loadCounts()

        XCTAssertEqual(store.counts?.counts.today, 7)
        XCTAssertEqual(api.countsCallCount, 0)

        try? await waitUntilTasksCondition(timeoutSeconds: 0.1) {
            api.countsCallCount == 1
        }
        XCTAssertEqual(api.countsCallCount, 1)
    }

    func testLoadCountsForceBypassesCacheAndFetchesImmediately() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let cachedCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 7, upcoming: 2, completed: 3),
            projects: [],
            groups: []
        )
        cache.set(key: CacheKeys.tasksCounts, value: cachedCounts, ttlSeconds: 60)

        let refreshedCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 4, upcoming: 2, completed: 3),
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
        let api = TasksStoreStubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        await store.load(selection: .none)

        XCTAssertEqual(store.selection, .none)
        XCTAssertEqual(store.tasks, [])
        XCTAssertEqual(api.listCallCount, 0)
    }

    func testSearchLoadPreservesGroupsAndProjectsWhenResponseOmitsMetadata() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let group = TaskGroup(id: "g1", title: "Work", updatedAt: nil)
        let project = TaskProject(id: "p1", title: "Roadmap", groupId: "g1", status: "active", updatedAt: nil)
        api.listResponsesByScope["today"] = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [TaskItem(id: "today-1", title: "Today task", status: "open")],
            projects: [project],
            groups: [group]
        )
        api.searchResponse = TaskListResponse(
            scope: "search",
            generatedAt: nil,
            tasks: [TaskItem(id: "search-1", title: "Search result", status: "open")],
            projects: nil,
            groups: nil
        )

        await store.load(selection: .today, force: true)
        await store.load(selection: .search(query: "search"), force: true)

        XCTAssertEqual(store.groups, [group])
        XCTAssertEqual(store.projects, [project])
        XCTAssertEqual(store.tasks.map(\.id), ["search-1"])
    }

    func testCachedListSkipsBackgroundRefreshWhenServerUnreachable() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let networkStatus = TasksStoreTestNetworkStatus(
            isNetworkAvailable: true,
            isServerReachable: false
        )
        let store = TasksStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: networkStatus
        )
        let cachedList = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [TaskItem(id: "cached-1", title: "Cached", status: "open")],
            projects: nil,
            groups: nil
        )
        cache.set(
            key: CacheKeys.tasksList(selectionKey: TaskSelection.today.cacheKey),
            value: cachedList,
            ttlSeconds: 60
        )

        await store.load(selection: .today)

        XCTAssertEqual(store.tasks.map(\.id), ["cached-1"])
        XCTAssertEqual(api.listCallCount, 0)
    }

    func testCachedListSkipsBackgroundRefreshWhenAppOfflineModeIsEnabled() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let networkStatus = TasksStoreTestNetworkStatus(
            isNetworkAvailable: true,
            isOffline: true,
            isServerReachable: true
        )
        let store = TasksStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: networkStatus
        )
        let cachedList = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [TaskItem(id: "cached-offline", title: "Cached offline", status: "open")],
            projects: nil,
            groups: nil
        )
        cache.set(
            key: CacheKeys.tasksList(selectionKey: TaskSelection.today.cacheKey),
            value: cachedList,
            ttlSeconds: 60
        )

        await store.load(selection: .today)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.tasks.map(\.id), ["cached-offline"])
        XCTAssertEqual(api.listCallCount, 0)
    }

    func testCachedListRefreshDoesNotOverrideNewerSelection() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
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
        api.suspendList(scope: "today")

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
        try? await waitUntilTasksCondition(timeoutSeconds: 0.1) {
            api.listCallCount == 1
        }

        await store.load(selection: .upcoming, force: true)
        XCTAssertEqual(store.selection, .upcoming)
        XCTAssertEqual(store.tasks, [upcomingTask])

        api.resumeList(scope: "today")
        try? await waitUntilTasksCondition(timeoutSeconds: 0.1) {
            api.listCallCount == 2
        }
        XCTAssertEqual(store.selection, .upcoming)
        XCTAssertEqual(store.tasks, [upcomingTask])
    }

    func testCachedListRefreshesCoalesceWhenAlreadyInFlight() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let cachedToday = TaskListResponse(scope: "today", generatedAt: nil, tasks: [], projects: nil, groups: nil)
        cache.set(
            key: CacheKeys.tasksList(selectionKey: TaskSelection.today.cacheKey),
            value: cachedToday,
            ttlSeconds: 60
        )
        api.suspendList(scope: "today")

        await store.load(selection: .today)
        try? await waitUntilTasksCondition(timeoutSeconds: 0.1) {
            api.listCallCount == 1
        }
        await store.load(selection: .today)
        api.resumeList(scope: "today")
        try? await waitUntilTasksCondition(timeoutSeconds: 0.1) {
            api.listCallCount == 1
        }

        XCTAssertEqual(api.listCallCount, 1)
    }

    func testCachedCountRefreshesCoalesceWhenAlreadyInFlight() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let cachedCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 7, upcoming: 2, completed: 3),
            projects: [],
            groups: []
        )
        cache.set(key: CacheKeys.tasksCounts, value: cachedCounts, ttlSeconds: 60)
        api.suspendCounts = true

        await store.loadCounts()
        try? await waitUntilTasksCondition(timeoutSeconds: 0.1) {
            api.countsCallCount == 1
        }
        await store.loadCounts()
        api.resumeCounts()
        try? await waitUntilTasksCondition(timeoutSeconds: 0.1) {
            api.countsCallCount == 1
        }

        XCTAssertEqual(api.countsCallCount, 1)
    }
}

@MainActor
final class TasksStoreLaunchLoadTests: XCTestCase {
    func testLoadForLaunchReturnsFalseWhenFreshTodayLoadFailsWithStaleTasksVisible() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let networkStatus = TasksStoreTestNetworkStatus(
            isNetworkAvailable: true,
            isServerReachable: false
        )
        let store = TasksStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: networkStatus
        )
        let staleTask = TaskItem(id: "stale-today", title: "Cached today", status: "open")
        let staleList = TaskListResponse(
            scope: "today",
            generatedAt: "stale",
            tasks: [staleTask],
            projects: nil,
            groups: nil
        )
        cache.set(
            key: CacheKeys.tasksList(selectionKey: TaskSelection.today.cacheKey),
            value: staleList,
            ttlSeconds: 60
        )

        await store.load(selection: .today)
        XCTAssertEqual(api.listCallCount, 0)
        networkStatus.isServerReachable = true
        api.listErrorsByScope["today"] = TasksStoreStubError.unused

        let didLoadFreshToday = await store.loadForLaunch(selection: .today)

        XCTAssertFalse(didLoadFreshToday)
        XCTAssertEqual(api.listCallCount, 1)
        XCTAssertEqual(store.selection, .today)
        XCTAssertEqual(store.tasks, [staleTask])
    }
}
