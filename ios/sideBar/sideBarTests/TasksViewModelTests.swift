import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class TasksViewModelTests: XCTestCase {
    func testCompleteTaskFailureRestoresTaskAndSetsError() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "task-1", title: "Follow up", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])
        api.applyResult = .failure(APIClientError.apiError("Sync failed"))

        let sut = makeSUT(api: api, networkAvailable: true)
        let viewModel = sut.viewModel; let store = sut.store
        await viewModel.load(selection: .today)

        await viewModel.completeTask(task: task)

        XCTAssertEqual(api.applyCallCount, 1)
        XCTAssertEqual(store.tasks.map(\.id), [task.id], "Failed optimistic updates should restore the task")
        XCTAssertEqual(viewModel.errorMessage, "Sync failed")
    }

    func testCompleteTaskSuccessRefreshesSelectionAndCounts() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "task-1", title: "Follow up", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])
        api.enqueueListResponse(scope: "today", tasks: [])
        api.enqueueListResponse(scope: "today", tasks: [])
        api.applyResult = .success(
            TaskSyncResponse(
                applied: ["op-1"],
                tasks: [],
                nextTasks: [],
                conflicts: [],
                updates: nil,
                serverUpdatedSince: nil
            )
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        let viewModel = sut.viewModel; let store = sut.store
        await viewModel.load(selection: .today)

        await viewModel.completeTask(task: task)
        await eventually {
            api.countsCallCount >= 1 && !store.tasks.contains(where: { $0.id == task.id })
        }

        XCTAssertGreaterThanOrEqual(api.listCallCount, 2, "Success path should refresh task data")
        XCTAssertGreaterThanOrEqual(api.countsCallCount, 1, "Success path should refresh counts")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUpdateSearchReturnsToLastNonSearchSelectionWhenQueryCleared() async {
        let api = TasksViewModelAPIStub()
        api.enqueueListResponse(scope: "today", tasks: [])
        api.searchResponse = TaskListResponse(
            scope: "search",
            generatedAt: nil,
            tasks: [TaskItem(id: "task-1", title: "Find me", status: "open")],
            projects: nil,
            groups: nil
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        let viewModel = sut.viewModel
        await viewModel.load(selection: .today)

        viewModel.updateSearch(query: "  find me  ")
        try? await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(viewModel.selection, .search(query: "find me"))

        viewModel.updateSearch(query: "   ")
        try? await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(viewModel.selection, .today)
    }

    func testCreateTaskOfflineQueuesPreviewAndClearsDraft() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(api: api, networkAvailable: false)
        let viewModel = sut.viewModel; let store = sut.store; let writeQueue = sut.writeQueue
        await viewModel.load(selection: .today)
        viewModel.startNewTask()

        await viewModel.createTask(title: " Offline task ", notes: "", dueDate: nil, listId: nil)
        await eventually {
            writeQueue.pendingCount >= 1
        }

        XCTAssertNil(viewModel.newTaskDraft)
        XCTAssertEqual(api.applyCallCount, 0, "Offline create should not call API apply")
        XCTAssertEqual(store.tasks.first?.title, "Offline task")
        XCTAssertEqual(store.tasks.first?.isPreview, true)
    }

    private struct SUT {
        let viewModel: TasksViewModel
        let store: TasksStore
        let writeQueue: WriteQueue
    }

    private func makeSUT(
        api: TasksViewModelAPIStub,
        networkAvailable: Bool
    ) -> SUT {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let networkStatus = TestNetworkStatus(isNetworkAvailable: networkAvailable)
        let store = TasksStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: networkStatus
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: ConnectivityMonitor(
                baseUrl: URL(string: "http://localhost")!,
                startMonitoring: false
            ),
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)
        let viewModel = TasksViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: networkStatus
        )
        return SUT(viewModel: viewModel, store: store, writeQueue: writeQueue)
    }

    private func eventually(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 25_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let started = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                XCTFail("Condition was not met before timeout")
                return
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }
}

@MainActor
private final class TestNetworkStatus: NetworkStatusProviding {
    var isNetworkAvailable: Bool
    var isOffline: Bool { !isNetworkAvailable }

    init(isNetworkAvailable: Bool) {
        self.isNetworkAvailable = isNetworkAvailable
    }
}

@MainActor
private final class TasksViewModelAPIStub: TasksProviding {
    var listCallCount = 0
    var searchCallCount = 0
    var countsCallCount = 0
    var applyCallCount = 0
    var applyResult: Result<TaskSyncResponse, Error> = .success(
        TaskSyncResponse(
            applied: [],
            tasks: [],
            nextTasks: [],
            conflicts: [],
            updates: nil,
            serverUpdatedSince: nil
        )
    )
    var searchResponse = TaskListResponse(scope: "search", generatedAt: nil, tasks: [], projects: nil, groups: nil)
    private var queuedListResponsesByScope: [String: [TaskListResponse]] = [:]

    func enqueueListResponse(scope: String, tasks: [TaskItem], groups: [TaskGroup]? = nil, projects: [TaskProject]? = nil) {
        let response = TaskListResponse(
            scope: scope,
            generatedAt: nil,
            tasks: tasks,
            projects: projects,
            groups: groups
        )
        queuedListResponsesByScope[scope, default: []].append(response)
    }

    func list(scope: String) async throws -> TaskListResponse {
        listCallCount += 1
        if var responses = queuedListResponsesByScope[scope], !responses.isEmpty {
            let first = responses.removeFirst()
            queuedListResponsesByScope[scope] = responses
            return first
        }
        return TaskListResponse(scope: scope, generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }

    func projectTasks(projectId: String) async throws -> TaskListResponse {
        _ = projectId
        throw TestStubError.unused
    }

    func groupTasks(groupId: String) async throws -> TaskListResponse {
        _ = groupId
        throw TestStubError.unused
    }

    func search(query: String) async throws -> TaskListResponse {
        _ = query
        searchCallCount += 1
        return searchResponse
    }

    func counts() async throws -> TaskCountsResponse {
        countsCallCount += 1
        return TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(inbox: 1, today: 1, upcoming: 1, completed: 1),
            projects: [],
            groups: []
        )
    }

    func createGroup(title: String) async throws -> TaskGroup {
        _ = title
        throw TestStubError.unused
    }

    func renameGroup(groupId: String, title: String) async throws -> TaskGroup {
        _ = groupId
        _ = title
        throw TestStubError.unused
    }

    func deleteGroup(groupId: String) async throws {
        _ = groupId
        throw TestStubError.unused
    }

    func createProject(title: String, groupId: String?) async throws -> TaskProject {
        _ = title
        _ = groupId
        throw TestStubError.unused
    }

    func renameProject(projectId: String, title: String) async throws -> TaskProject {
        _ = projectId
        _ = title
        throw TestStubError.unused
    }

    func deleteProject(projectId: String) async throws {
        _ = projectId
        throw TestStubError.unused
    }

    func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse {
        _ = payload
        applyCallCount += 1
        return try applyResult.get()
    }

    func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse {
        _ = payload
        throw TestStubError.unused
    }
}

private enum TestStubError: Error {
    case unused
}
