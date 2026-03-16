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
        let viewModel = sut.viewModel
        let store = sut.store
        await viewModel.load(selection: .today)

        await viewModel.completeTask(task: task)

        XCTAssertEqual(api.applyCallCount, 1)
        XCTAssertEqual(store.tasks.map(\.id), [task.id], "Failed optimistic updates should restore the task")
        XCTAssertEqual(viewModel.errorMessage, "Sync failed")
    }

    func testCompleteTaskSuccessKeepsSelectionStableAndRefreshesCounts() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "task-1", title: "Follow up", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])
        // refreshWidgetData() still fetches today's list after a successful completion.
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
        let viewModel = sut.viewModel
        let store = sut.store
        await viewModel.load(selection: .today)
        XCTAssertEqual(api.listCallCount, 1)

        await viewModel.completeTask(task: task)
        await eventually {
            api.countsCallCount >= 1
                && api.listCallCount >= 2
                && !store.tasks.contains(where: { $0.id == task.id })
        }

        XCTAssertEqual(
            api.listCallCount,
            2,
            "Success path should avoid forcing a main list reload and only refresh widget data"
        )
        XCTAssertGreaterThanOrEqual(api.countsCallCount, 1, "Success path should refresh counts")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUpdateSearchReturnsToLastNonSearchSelectionWhenQueryClearedImmediately() async {
        let api = TasksViewModelAPIStub()
        api.enqueueListResponse(scope: "today", tasks: [])
        api.searchResponse = TaskListResponse(
            scope: "search",
            generatedAt: nil,
            tasks: [TaskItem(id: "task-1", title: "Find me", status: "open")],
            projects: nil,
            groups: nil
        )

        let sut = makeSUT(
            api: api,
            networkAvailable: true,
            searchDebounceNanoseconds: 0
        )
        let viewModel = sut.viewModel
        await viewModel.load(selection: .today)

        viewModel.updateSearch(query: "  find me  ")
        await eventually {
            viewModel.selection == .search(query: "find me")
        }

        api.enqueueListResponse(scope: "today", tasks: [])
        viewModel.updateSearch(query: "   ")
        XCTAssertEqual(viewModel.searchQuery, "")
        await eventually(timeoutNanoseconds: 300_000_000) {
            viewModel.selection == .today
        }
    }

    func testClearSearchQueryCancelsPendingDebouncedSearch() async {
        let api = TasksViewModelAPIStub()
        api.enqueueListResponse(scope: "today", tasks: [])

        let sut = makeSUT(
            api: api,
            networkAvailable: true,
            searchDebounceNanoseconds: 100_000_000
        )
        let viewModel = sut.viewModel
        await viewModel.load(selection: .today)

        viewModel.updateSearch(query: "follow up")
        viewModel.clearSearchQuery()
        await eventually {
            viewModel.searchQuery.isEmpty
        }

        XCTAssertEqual(api.searchCallCount, 0)
        XCTAssertEqual(viewModel.selection, .today)
        XCTAssertEqual(viewModel.searchQuery, "")
    }

    func testCreateTaskOfflineQueuesPreviewAndClearsDraft() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(api: api, networkAvailable: false)
        let viewModel = sut.viewModel
        let store = sut.store
        let writeQueue = sut.writeQueue
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

    func testCreateTaskQueuesWhenServerIsUnreachable() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(api: api, networkAvailable: true, serverReachable: false)
        let viewModel = sut.viewModel
        let store = sut.store
        let writeQueue = sut.writeQueue
        await viewModel.load(selection: .today)
        viewModel.startNewTask()

        await viewModel.createTask(title: "Queued while server down", notes: "", dueDate: nil, listId: nil)
        await eventually {
            writeQueue.pendingCount >= 1
        }

        XCTAssertEqual(api.applyCallCount, 0, "Should queue when backend is unreachable")
        XCTAssertNil(viewModel.newTaskDraft)
        XCTAssertEqual(store.tasks.first?.title, "Queued while server down")
        XCTAssertEqual(store.tasks.first?.isPreview, true)
    }

    func testPreferredLoadSelectionDefaultsToTodayWhenSelectionIsNone() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(api: api, networkAvailable: true)

        XCTAssertEqual(sut.viewModel.selection, .none)
        XCTAssertEqual(sut.viewModel.preferredLoadSelection, .today)
    }

    // MARK: - Load with different selections

    func testLoadUpcomingSelectionSetsSelectionAndFetchesList() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Future task", status: "open", deadline: "2025-06-01")
        api.enqueueListResponse(scope: "upcoming", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        let viewModel = sut.viewModel
        await viewModel.load(selection: .upcoming)

        XCTAssertEqual(viewModel.selection, .upcoming)
        XCTAssertEqual(api.listCallCount, 1)
        XCTAssertTrue(sut.store.tasks.contains(where: { $0.id == "t1" }))
    }

    func testLoadGroupSelectionCallsGroupTasksEndpoint() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Group task", status: "open", groupId: "g1")
        api.groupTasksResponse = TaskListResponse(
            scope: "group", generatedAt: nil, tasks: [task], projects: nil, groups: nil
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .group(id: "g1"))

        XCTAssertEqual(api.groupTasksCallCount, 1)
        XCTAssertEqual(sut.viewModel.selection, .group(id: "g1"))
        XCTAssertTrue(sut.store.tasks.contains(where: { $0.id == "t1" }))
    }

    func testLoadProjectSelectionCallsProjectTasksEndpoint() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Project task", status: "open", projectId: "p1")
        api.projectTasksResponse = TaskListResponse(
            scope: "project", generatedAt: nil, tasks: [task], projects: nil, groups: nil
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .project(id: "p1"))

        XCTAssertEqual(api.projectTasksCallCount, 1)
        XCTAssertEqual(sut.viewModel.selection, .project(id: "p1"))
        XCTAssertTrue(sut.store.tasks.contains(where: { $0.id == "t1" }))
    }

    // MARK: - Task operations error paths

    func testRenameTaskFailureSetsError() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Old name", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])
        api.applyResult = .failure(APIClientError.apiError("Rename failed"))

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)

        await sut.viewModel.renameTask(task: task, title: "New name")

        XCTAssertEqual(api.applyCallCount, 1)
        XCTAssertNotNil(sut.viewModel.errorMessage)
    }

    func testDeleteTaskSuccessRemovesFromStore() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Delete me", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])
        // After apply, the refresh returns empty
        api.enqueueListResponse(scope: "today", tasks: [])
        api.enqueueListResponse(scope: "today", tasks: [])
        api.applyResult = .success(
            TaskSyncResponse(applied: ["op-1"], tasks: [], nextTasks: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        XCTAssertTrue(sut.store.tasks.contains(where: { $0.id == "t1" }))

        await sut.viewModel.deleteTask(task: task)
        await eventually {
            !sut.store.tasks.contains(where: { $0.id == "t1" })
        }

        XCTAssertEqual(api.applyCallCount, 1)
        XCTAssertFalse(sut.store.tasks.contains(where: { $0.id == "t1" }))
    }

    func testDeferTaskOffsetsDeadline() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Defer me", status: "open", deadline: "2025-03-15", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])
        api.enqueueListResponse(scope: "today", tasks: [])
        api.applyResult = .success(
            TaskSyncResponse(applied: ["op-1"], tasks: [], nextTasks: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)

        await sut.viewModel.deferTask(task: task, days: 3)

        XCTAssertEqual(api.applyCallCount, 1)
        // Verify the payload contains the offset date
        let sentDueDate = api.lastApplyPayload?.operations.first?.dueDate
        XCTAssertEqual(sentDueDate, "2025-03-18")
    }

    func testAutosaveNotesCallsApplyWithoutRefreshingSelectionOrCounts() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Draft", status: "open", notes: "Old", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        XCTAssertEqual(api.listCallCount, 1)
        XCTAssertEqual(api.countsCallCount, 0)

        await sut.viewModel.autosaveNotes(task: task, notes: "Updated")

        XCTAssertEqual(api.applyCallCount, 1)
        XCTAssertEqual(api.listCallCount, 1, "Autosave should avoid full list refresh")
        XCTAssertEqual(api.countsCallCount, 0, "Autosave should avoid counts refresh")
        let operation = api.lastApplyPayload?.operations.first
        XCTAssertEqual(operation?.op, "notes")
        XCTAssertEqual(operation?.notes, "Updated")
    }

    func testUpdateNotesRefreshesSelectionAndCounts() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Draft", status: "open", notes: "Old", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])
        let updatedTask = TaskItem(id: "t1", title: "Draft", status: "open", notes: "Updated", updatedAt: "u2")
        api.enqueueListResponse(scope: "today", tasks: [updatedTask])
        api.enqueueListResponse(scope: "today", tasks: [updatedTask])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)

        await sut.viewModel.updateNotes(task: task, notes: "Updated")

        XCTAssertEqual(api.applyCallCount, 1)
        XCTAssertGreaterThanOrEqual(api.listCallCount, 3, "Manual save should refresh list and widget data")
        XCTAssertGreaterThanOrEqual(api.countsCallCount, 1, "Manual save should refresh counts")
    }

    // MARK: - New task creation

    func testCreateTaskOnlineCallsApplyAndRefreshes() async {
        let api = TasksViewModelAPIStub()
        api.enqueueListResponse(scope: "today", tasks: [])
        // Responses for post-create refresh
        api.enqueueListResponse(scope: "today", tasks: [TaskItem(id: "t1", title: "Buy milk", status: "open")])
        api.enqueueListResponse(scope: "today", tasks: [TaskItem(id: "t1", title: "Buy milk", status: "open")])
        api.applyResult = .success(
            TaskSyncResponse(applied: ["op-1"], tasks: [], nextTasks: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        sut.viewModel.startNewTask()

        await sut.viewModel.createTask(title: "Buy milk", notes: "", dueDate: Date(), listId: nil)

        XCTAssertEqual(api.applyCallCount, 1)
        XCTAssertNil(sut.viewModel.newTaskDraft, "Draft should be cleared after success")
        XCTAssertGreaterThanOrEqual(api.listCallCount, 2, "Should refresh list after create")
    }

    func testCreateTaskTrimsWhitespaceFromTitle() async {
        let api = TasksViewModelAPIStub()
        api.enqueueListResponse(scope: "today", tasks: [])
        api.enqueueListResponse(scope: "today", tasks: [])
        api.enqueueListResponse(scope: "today", tasks: [])
        api.applyResult = .success(
            TaskSyncResponse(applied: ["op-1"], tasks: [], nextTasks: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        sut.viewModel.startNewTask()

        await sut.viewModel.createTask(title: "  Buy milk  ", notes: "", dueDate: nil, listId: nil)

        XCTAssertEqual(api.applyCallCount, 1)
        let sentTitle = api.lastApplyPayload?.operations.first?.title
        XCTAssertEqual(sentTitle, "Buy milk")
    }

    // MARK: - Group/project management

    func testCreateGroupCallsAPIAndRefreshesCounts() async {
        let api = TasksViewModelAPIStub()
        api.enqueueListResponse(scope: "today", tasks: [])
        api.enqueueListResponse(scope: "today", tasks: [])
        api.createGroupResult = .success(TaskGroup(id: "g1", title: "Work", updatedAt: nil))

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)

        try? await sut.viewModel.createGroup(title: "Work")

        XCTAssertEqual(api.createGroupCallCount, 1)
        XCTAssertGreaterThanOrEqual(api.countsCallCount, 1, "Should refresh counts after creating group")
    }

    func testDeleteGroupFallsBackToNoneSelection() async {
        let api = TasksViewModelAPIStub()
        let group = TaskGroup(id: "g1", title: "Work", updatedAt: nil)
        api.groupTasksResponse = TaskListResponse(
            scope: "group", generatedAt: nil, tasks: [], projects: nil, groups: [group]
        )
        api.deleteGroupResult = .success(())
        // Response for the post-delete reload (will load .none)
        api.enqueueListResponse(scope: "today", tasks: [])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .group(id: "g1"))
        XCTAssertEqual(sut.viewModel.selection, .group(id: "g1"))

        try? await sut.viewModel.deleteGroup(groupId: "g1")

        // ViewModel should fall back to .none when the viewed group is deleted
        XCTAssertEqual(sut.viewModel.selection, .none)
        XCTAssertEqual(api.deleteGroupCallCount, 1)
    }

    func testDeleteProjectFallsBackToNoneSelection() async {
        let api = TasksViewModelAPIStub()
        let project = TaskProject(id: "p1", title: "Alpha", groupId: "g1", status: "active", updatedAt: nil)
        api.projectTasksResponse = TaskListResponse(
            scope: "project", generatedAt: nil, tasks: [], projects: [project], groups: nil
        )
        api.deleteProjectResult = .success(())
        // Response for the post-delete reload
        api.enqueueListResponse(scope: "today", tasks: [])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .project(id: "p1"))
        XCTAssertEqual(sut.viewModel.selection, .project(id: "p1"))

        try? await sut.viewModel.deleteProject(projectId: "p1")

        // ViewModel should fall back to .none when the viewed project is deleted
        XCTAssertEqual(sut.viewModel.selection, .none)
        XCTAssertEqual(api.deleteProjectCallCount, 1)
    }

    // MARK: - Helpers

    private struct SUT {
        let viewModel: TasksViewModel
        let store: TasksStore
        let writeQueue: WriteQueue
    }

    private func makeSUT(
        api: TasksViewModelAPIStub,
        networkAvailable: Bool,
        serverReachable: Bool = true,
        searchDebounceNanoseconds: UInt64 = 350_000_000,
        realtimeRefreshDelayNanoseconds: UInt64 = 200_000_000
    ) -> SUT {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let networkStatus = TasksTestNetworkStatus(
            isNetworkAvailable: networkAvailable,
            isServerReachable: serverReachable
        )
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
            networkStatus: networkStatus,
            searchDebounceNanoseconds: searchDebounceNanoseconds,
            realtimeRefreshDelayNanoseconds: realtimeRefreshDelayNanoseconds
        )
        return SUT(viewModel: viewModel, store: store, writeQueue: writeQueue)
    }

    private func eventually(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 0,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let started = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                XCTFail("Condition was not met before timeout")
                return
            }
            if pollNanoseconds == 0 {
                await Task.yield()
            } else {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
        }
    }
}
