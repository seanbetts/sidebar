// swiftlint:disable file_length
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
// swiftlint:disable:next type_body_length
final class TasksViewModelTests: XCTestCase {
    func testTaskListLoadStateTracksEmptyFailureAndRecovery() async {
        let api = TasksViewModelAPIStub()
        api.listErrorByScope["today"] = APIClientError.requestFailed(503)
        let sut = makeSUT(api: api, networkAvailable: true)
        let viewModel = sut.viewModel

        await viewModel.load(selection: .today)

        XCTAssertEqual(
            viewModel.listLoadState,
            .failed("Server is busy right now. Please try again.")
        )

        api.listErrorByScope.removeValue(forKey: "today")
        api.enqueueListResponse(scope: "today", tasks: [])
        await viewModel.load(selection: .today, force: true)

        XCTAssertEqual(viewModel.listLoadState, .loaded)
        XCTAssertTrue(viewModel.listLoadState.canShowEmptyState)
    }

    func testCompleteTaskQueuesAndRemovesTaskLocally() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "task-1", title: "Follow up", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        let viewModel = sut.viewModel
        let store = sut.store
        await viewModel.load(selection: .today)

        await viewModel.completeTask(task: task)

        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertFalse(store.tasks.contains { $0.id == task.id })
        XCTAssertNil(viewModel.errorMessage)
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testRenameTaskQueuesAndUpdatesLoadedContent() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "task-1", title: "Follow up", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)

        await sut.viewModel.renameTask(task: task, title: "Renamed")

        XCTAssertEqual(sut.store.tasks.map(\.id), [task.id])
        XCTAssertEqual(sut.store.tasks.first?.title, "Renamed")
        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertNil(sut.viewModel.errorMessage)
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testCompleteTaskKeepsSelectionStableAndQueuesWithoutRefreshingCounts() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "task-1", title: "Follow up", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        let viewModel = sut.viewModel
        let store = sut.store
        await viewModel.load(selection: .today)
        XCTAssertEqual(api.listCallCount, 1)

        await viewModel.completeTask(task: task)
        await eventually {
            sut.writeQueue.pendingCount >= 1
                && !store.tasks.contains(where: { $0.id == task.id })
        }

        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertEqual(api.listCallCount, 1, "Queued completion should not reload the list")
        XCTAssertEqual(api.countsCallCount, 0, "Queued completion should update counts locally")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testReopenTaskQueuesAndRemovesTaskFromCompletedSelection() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "task-1", title: "Done", status: "completed", updatedAt: "u1")
        api.enqueueListResponse(scope: "completed", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .completed)

        await sut.viewModel.reopenTask(task: task)

        XCTAssertFalse(sut.store.tasks.contains { $0.id == task.id })
        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertNil(sut.viewModel.errorMessage)
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testReopenTaskSuccessRemovesTaskFromCompletedSelectionAndUpdatesTodayCount() async {
        let api = TasksViewModelAPIStub()
        let today = TasksUtils.formatDateKey(Date())
        let task = TaskItem(
            id: "task-1",
            title: "Done today",
            status: "completed",
            deadline: today,
            updatedAt: "u1"
        )
        api.enqueueListResponse(scope: "completed", tasks: [task])
        api.countsResponse = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 0, upcoming: 1, completed: 1),
            projects: [],
            groups: []
        )
        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .completed)
        await sut.viewModel.loadCounts(force: true)

        await sut.viewModel.reopenTask(task: task)
        await eventually {
            sut.store.counts?.counts.today == 1 && !sut.store.tasks.contains(where: { $0.id == task.id })
        }

        XCTAssertEqual(api.applyCallCount, 0)
        await eventually { sut.writeQueue.pendingCount >= 1 }
        XCTAssertFalse(sut.store.tasks.contains(where: { $0.id == task.id }))
        XCTAssertEqual(sut.store.counts?.counts.today, 1)
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

    func testCreateTaskQueuesWhenAppOfflineModeIsEnabled() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(api: api, networkAvailable: true, serverReachable: true, isOffline: true)
        let viewModel = sut.viewModel
        let store = sut.store
        let writeQueue = sut.writeQueue
        await viewModel.load(selection: .today)
        viewModel.startNewTask()

        await viewModel.createTask(title: "Queued while app offline", notes: "", dueDate: nil, listId: nil)
        await eventually {
            writeQueue.pendingCount >= 1
        }

        XCTAssertEqual(api.applyCallCount, 0, "Explicit offline mode should queue instead of calling apply")
        XCTAssertNil(viewModel.newTaskDraft)
        XCTAssertEqual(store.tasks.first?.title, "Queued while app offline")
        XCTAssertEqual(store.tasks.first?.isPreview, true)
    }

    func testCreateTaskOfflineUpdatesTodayCountOptimistically() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(api: api, networkAvailable: false)
        let viewModel = sut.viewModel
        let store = sut.store
        api.countsResponse = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 1, upcoming: 2, completed: 3),
            projects: [],
            groups: []
        )

        await viewModel.load(selection: .today)
        await viewModel.loadCounts(force: true)
        viewModel.startNewTask()
        await viewModel.createTask(title: "Today task", notes: "", dueDate: Date(), listId: nil)

        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertEqual(store.counts?.counts.today, 2)
    }

    func testCreateTaskOnlineQueuesAndClearsDraftWithoutApplyCall() async {
        let api = TasksViewModelAPIStub()
        api.suspendNextApply()
        let sut = makeSUT(api: api, networkAvailable: true)
        let viewModel = sut.viewModel

        await viewModel.load(selection: .today)
        viewModel.startNewTask()
        await viewModel.createTask(title: "Weak signal task", notes: "", dueDate: Date(), listId: nil)

        XCTAssertNil(viewModel.newTaskDraft)
        XCTAssertFalse(viewModel.newTaskSaving)
        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertEqual(sut.store.tasks.first?.title, "Weak signal task")
        XCTAssertEqual(sut.store.tasks.first?.isPreview, true)
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testReopenDueTodayClearsNotificationCompletionTracking() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(
            id: UUID().uuidString,
            title: "Reopen notification task",
            status: "completed",
            deadline: TasksUtils.formatDateKey(Date())
        )
        let sut = makeSUT(api: api, networkAvailable: true)
        sut.widgetDataManager.storeTaskData(
            WidgetTaskData(
                tasks: [],
                totalCount: 0,
                progressCompletedCount: 1,
                progressTotalCount: 1,
                optimisticallyCompletedTaskIds: [task.id],
                pendingOptimisticCompletionTaskIds: []
            ),
            for: .today
        )

        let queued = await sut.viewModel.reopenTask(task: task)

        XCTAssertTrue(queued)
        let snapshot = sut.widgetDataManager.loadTaskData(for: .today)
        XCTAssertEqual(snapshot.totalCount, 1)
        XCTAssertEqual(snapshot.progressCompletedCount, 0)
        XCTAssertTrue(snapshot.optimisticallyCompletedTaskIds.isEmpty)
        XCTAssertTrue(snapshot.pendingOptimisticCompletionTaskIds.isEmpty)
    }

    func testCompleteTaskOnlineQueuesAndDoesNotCallApply() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(
            id: "task-1",
            title: "Finish",
            status: "open",
            deadline: TasksUtils.formatDateKey(Date()),
            notes: nil,
            projectId: nil,
            groupId: nil,
            repeating: false,
            repeatTemplate: nil,
            recurrenceRule: nil,
            nextInstanceDate: nil,
            updatedAt: "2026-06-09T10:00:00Z",
            deletedAt: nil
        )
        api.enqueueListResponse(scope: "today", tasks: [task])
        let sut = makeSUT(api: api, networkAvailable: true)

        await sut.viewModel.load(selection: .today)
        let completed = await sut.viewModel.completeTask(task: task)

        XCTAssertTrue(completed)
        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertFalse(sut.store.tasks.contains { $0.id == "task-1" })
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testCompleteTaskByIdentifierQueuesWithoutLoadedTask() async {
        let api = TasksViewModelAPIStub()
        api.countsResponse = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 1, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )
        let sut = makeSUT(api: api, networkAvailable: false)
        await sut.viewModel.loadCounts(force: true)
        let taskId = UUID().uuidString
        sut.widgetDataManager.storeTaskData(
            WidgetTaskData(
                tasks: [WidgetTask(id: taskId, title: "Notification task")],
                totalCount: 1,
                progressCompletedCount: 0,
                progressTotalCount: 1
            ),
            for: .today
        )

        let result = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)

        XCTAssertEqual(result, .queued)
        XCTAssertEqual(sut.store.counts?.counts.today, 0)
        XCTAssertEqual(api.applyCallCount, 0)
        await eventually { sut.writeQueue.pendingCount == 1 }
        let widgetSnapshot = sut.widgetDataManager.loadTaskData(for: .today)
        XCTAssertTrue(widgetSnapshot.tasks.isEmpty)
        XCTAssertEqual(widgetSnapshot.totalCount, 0)
        XCTAssertEqual(widgetSnapshot.progressCompletedCount, 1)
        XCTAssertEqual(widgetSnapshot.progressTotalCount, 1)
    }

    func testNotificationCompletionUpdatesOffscreenDueTodayWidgetOnlyOnce() async {
        let api = TasksViewModelAPIStub()
        let taskId = UUID().uuidString
        let visibleTasks = (0..<10).map {
            TaskItem(
                id: "visible-\($0)",
                title: String(format: "%02d Visible", $0),
                status: "open",
                deadline: TasksUtils.formatDateKey(Date())
            )
        }
        let offscreenTask = TaskItem(
            id: taskId,
            title: "ZZ Offscreen",
            status: "open",
            deadline: TasksUtils.formatDateKey(Date())
        )
        api.enqueueListResponse(scope: "today", tasks: visibleTasks + [offscreenTask])
        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        let initialSnapshot = sut.widgetDataManager.loadTaskData(for: .today)
        XCTAssertEqual(initialSnapshot.tasks.count, 10)
        XCTAssertEqual(initialSnapshot.totalCount, 11)
        XCTAssertFalse(initialSnapshot.tasks.contains { $0.id == taskId })

        let first = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)
        let second = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)

        XCTAssertEqual(first, .queued)
        XCTAssertEqual(second, .queued)
        let snapshot = sut.widgetDataManager.loadTaskData(for: .today)
        XCTAssertEqual(snapshot.tasks.count, 10)
        XCTAssertEqual(snapshot.totalCount, 10)
        XCTAssertEqual(snapshot.progressCompletedCount, 1)
        XCTAssertEqual(snapshot.progressTotalCount, 11)
        XCTAssertEqual(snapshot.optimisticallyCompletedTaskIds, [taskId])
        XCTAssertEqual(snapshot.pendingOptimisticCompletionTaskIds, [taskId])
    }

    func testNotificationCompletionSurvivesStaleSameDayWidgetRefresh() async {
        let api = TasksViewModelAPIStub()
        let taskId = UUID().uuidString
        let visibleTasks = (0..<10).map {
            TaskItem(
                id: "visible-\($0)",
                title: String(format: "%02d Visible", $0),
                status: "open",
                deadline: TasksUtils.formatDateKey(Date())
            )
        }
        let offscreenTask = TaskItem(
            id: taskId,
            title: "ZZ Offscreen",
            status: "open",
            deadline: TasksUtils.formatDateKey(Date())
        )
        let staleTasks = visibleTasks + [offscreenTask]
        api.enqueueListResponse(scope: "today", tasks: staleTasks)
        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        let firstResult = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)
        XCTAssertEqual(firstResult, .queued)

        api.enqueueListResponse(scope: "today", tasks: staleTasks)
        await sut.viewModel.load(selection: .today, force: true)
        let refreshedSnapshot = sut.widgetDataManager.loadTaskData(for: .today)

        XCTAssertEqual(refreshedSnapshot.totalCount, 10)
        XCTAssertEqual(refreshedSnapshot.progressCompletedCount, 1)
        XCTAssertEqual(refreshedSnapshot.progressTotalCount, 11)
        XCTAssertEqual(refreshedSnapshot.optimisticallyCompletedTaskIds, [taskId])
        XCTAssertEqual(refreshedSnapshot.pendingOptimisticCompletionTaskIds, [taskId])

        let repeatedResult = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)
        XCTAssertEqual(repeatedResult, .queued)
        let repeatedSnapshot = sut.widgetDataManager.loadTaskData(for: .today)
        XCTAssertEqual(repeatedSnapshot, refreshedSnapshot)
    }

    func testNotificationCompletionIgnoresDuplicateAfterServerConvergence() async {
        let api = TasksViewModelAPIStub()
        let taskId = UUID().uuidString
        let visibleTasks = (0..<10).map {
            TaskItem(
                id: "visible-\($0)",
                title: String(format: "%02d Visible", $0),
                status: "open",
                deadline: TasksUtils.formatDateKey(Date())
            )
        }
        let offscreenTask = TaskItem(
            id: taskId,
            title: "ZZ Offscreen",
            status: "open",
            deadline: TasksUtils.formatDateKey(Date())
        )
        api.countsResponse = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 11, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )
        api.enqueueListResponse(scope: "today", tasks: visibleTasks + [offscreenTask])
        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        await sut.viewModel.loadCounts(force: true)

        let firstResult = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)
        await eventually { sut.writeQueue.pendingCount == 1 }
        XCTAssertEqual(firstResult, .queued)
        XCTAssertEqual(sut.store.counts?.counts.today, 10)

        api.enqueueListResponse(scope: "today", tasks: visibleTasks)
        await sut.viewModel.refreshWidgetData()
        let convergedSnapshot = sut.widgetDataManager.loadTaskData(for: .today)
        XCTAssertEqual(convergedSnapshot.totalCount, 10)
        XCTAssertEqual(convergedSnapshot.progressCompletedCount, 1)
        XCTAssertEqual(convergedSnapshot.optimisticallyCompletedTaskIds, [taskId])
        XCTAssertTrue(convergedSnapshot.pendingOptimisticCompletionTaskIds.isEmpty)

        let duplicateResult = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)
        XCTAssertEqual(duplicateResult, .queued)
        XCTAssertEqual(sut.writeQueue.pendingCount, 1)
        XCTAssertEqual(sut.store.counts?.counts.today, 10)
        XCTAssertEqual(
            sut.widgetDataManager.loadTaskData(for: .today),
            convergedSnapshot
        )
    }

    func testNotificationCompletionClearsPreviousDayHandledIdBeforeQueueing() async {
        let api = TasksViewModelAPIStub()
        let taskId = UUID().uuidString
        let sut = makeSUT(api: api, networkAvailable: true)
        let previousDay = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: Date()
        )!
        sut.widgetDataManager.storeTaskData(
            WidgetTaskData(
                tasks: [WidgetTask(id: taskId, title: "Due today")],
                totalCount: 1,
                progressCompletedCount: 1,
                progressTotalCount: 1,
                optimisticallyCompletedTaskIds: [taskId],
                pendingOptimisticCompletionTaskIds: [],
                lastUpdated: previousDay
            ),
            for: .today
        )

        let result = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)

        XCTAssertEqual(result, .queued)
        XCTAssertEqual(sut.writeQueue.pendingCount, 1)
        let snapshot = sut.widgetDataManager.loadTaskData(for: .today)
        XCTAssertTrue(Calendar.current.isDateInToday(snapshot.lastUpdated))
        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertEqual(snapshot.totalCount, 0)
        XCTAssertEqual(snapshot.progressCompletedCount, 0)
        XCTAssertEqual(snapshot.progressTotalCount, 0)
        XCTAssertEqual(snapshot.optimisticallyCompletedTaskIds, [taskId])
        XCTAssertEqual(snapshot.pendingOptimisticCompletionTaskIds, [taskId])
    }

    func testNotificationCompletionDiscardsPersistedWriteWhenAccountChangesDuringEnqueue() async {
        let api = TasksViewModelAPIStub()
        let taskId = UUID().uuidString
        let gate = TasksNotificationEnqueuePersistenceGate()
        let sut = makeSUT(api: api, networkAvailable: false)
        let receivingScope = sut.accountScopeCoordinator.currentScope!
        sut.store.tasks = [TaskItem(id: taskId, title: "Account A task", status: "open")]
        sut.store.counts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 1, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )
        sut.widgetDataManager.storeTaskData(
            WidgetTaskData(
                tasks: [WidgetTask(id: taskId, title: "Account A task")],
                totalCount: 1
            ),
            for: .today
        )

        let completion = Task { @MainActor in
            await sut.viewModel.completeDueTodayTaskFromNotification(
                taskId: taskId,
                accountScope: receivingScope,
                afterEnqueuePersistence: { await gate.suspendAfterPersistence() }
            )
        }
        await gate.waitUntilSuspended()
        await eventually { sut.writeQueue.pendingCount == 1 }

        sut.accountScopeCoordinator.invalidate()
        _ = sut.accountScopeCoordinator.activate(accountId: UUID().uuidString)
        let accountBTask = TaskItem(id: "account-b-task", title: "Account B task", status: "open")
        let accountBCounts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 4, upcoming: 2, completed: 1),
            projects: [],
            groups: []
        )
        let accountBWidget = WidgetTaskData(
            tasks: [WidgetTask(id: accountBTask.id, title: accountBTask.title)],
            totalCount: 4,
            progressCompletedCount: 1,
            progressTotalCount: 5
        )
        sut.store.reset()
        sut.store.tasks = [accountBTask]
        sut.store.counts = accountBCounts
        sut.widgetDataManager.storeTaskData(accountBWidget, for: .today)
        await gate.release()

        let result = await completion.value

        XCTAssertEqual(result, .declined)
        XCTAssertEqual(sut.writeQueue.pendingCount, 0)
        XCTAssertEqual(sut.store.tasks, [accountBTask])
        XCTAssertEqual(sut.store.counts, accountBCounts)
        let storedAccountBWidget = sut.widgetDataManager.loadTaskData(for: .today)
        XCTAssertEqual(storedAccountBWidget.tasks, accountBWidget.tasks)
        XCTAssertEqual(storedAccountBWidget.totalCount, accountBWidget.totalCount)
        XCTAssertEqual(
            storedAccountBWidget.progressCompletedCount,
            accountBWidget.progressCompletedCount
        )
        XCTAssertEqual(storedAccountBWidget.progressTotalCount, accountBWidget.progressTotalCount)
        XCTAssertEqual(
            storedAccountBWidget.optimisticallyCompletedTaskIds,
            accountBWidget.optimisticallyCompletedTaskIds
        )
        XCTAssertEqual(
            storedAccountBWidget.pendingOptimisticCompletionTaskIds,
            accountBWidget.pendingOptimisticCompletionTaskIds
        )
        XCTAssertEqual(api.applyCallCount, 0)
    }

    func testOverlappingNotificationCompletionAwaitsOriginalQueuedResult() async {
        let api = TasksViewModelAPIStub()
        let taskId = UUID().uuidString
        let gate = TasksNotificationEnqueuePersistenceGate()
        let sut = makeSUT(api: api, networkAvailable: true)
        sut.widgetDataManager.storeTaskData(
            WidgetTaskData(
                tasks: [WidgetTask(id: taskId, title: "Notification task")],
                totalCount: 1,
                progressCompletedCount: 0,
                progressTotalCount: 1
            ),
            for: .today
        )

        let original = Task { @MainActor in
            await sut.viewModel.completeDueTodayTaskFromNotification(
                taskId: taskId,
                afterEnqueuePersistence: { await gate.suspendAfterPersistence() }
            )
        }
        await gate.waitUntilSuspended()
        await eventually { sut.writeQueue.pendingCount == 1 }

        var duplicateFinished = false
        let duplicateStarted = expectation(description: "Duplicate started")
        let duplicate = Task { @MainActor in
            duplicateStarted.fulfill()
            let result = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)
            duplicateFinished = true
            return result
        }
        await fulfillment(of: [duplicateStarted], timeout: 1)
        await Task.yield()

        XCTAssertFalse(duplicateFinished)
        await gate.release()
        let results = await (original.value, duplicate.value)

        XCTAssertEqual(results.0, .queued)
        XCTAssertEqual(results.1, .queued)
        XCTAssertEqual(sut.writeQueue.pendingCount, 1)
        let snapshot = sut.widgetDataManager.loadTaskData(for: .today)
        XCTAssertEqual(snapshot.totalCount, 0)
        XCTAssertEqual(snapshot.progressCompletedCount, 1)
        XCTAssertEqual(snapshot.optimisticallyCompletedTaskIds, [taskId])
        XCTAssertEqual(snapshot.pendingOptimisticCompletionTaskIds, [taskId])
    }

    func testOverlappingNotificationCompletionSharesQueueFullResult() async {
        let api = TasksViewModelAPIStub()
        let taskId = UUID().uuidString
        let gate = TasksNotificationEnqueuePersistenceGate()
        let sut = makeSUT(
            api: api,
            networkAvailable: false,
            maxPendingWrites: 1
        )
        await sut.viewModel.renameTask(
            task: TaskItem(id: "queued-task", title: "Queued", status: "open"),
            title: "Already queued"
        )
        await eventually { sut.writeQueue.pendingCount == 1 }

        let original = Task { @MainActor in
            await sut.viewModel.completeDueTodayTaskFromNotification(
                taskId: taskId,
                beforeEnqueue: { await gate.suspendAfterPersistence() }
            )
        }
        await gate.waitUntilSuspended()
        let duplicate = Task { @MainActor in
            await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)
        }
        await gate.release()
        let results = await (original.value, duplicate.value)

        XCTAssertEqual(results.0, .failed(.queueFull))
        XCTAssertEqual(results.1, .failed(.queueFull))
        XCTAssertEqual(sut.writeQueue.pendingCount, 1)
        XCTAssertFalse(
            sut.widgetDataManager.loadTaskData(for: .today)
                .optimisticallyCompletedTaskIds.contains(taskId)
        )
    }

    func testOverlappingNotificationCompletionSharesUnavailableResult() async {
        let api = TasksViewModelAPIStub()
        let taskId = UUID().uuidString
        let gate = TasksNotificationEnqueuePersistenceGate()
        let sut = makeSUT(
            api: api,
            networkAvailable: false,
            attachWriteQueue: false
        )

        let original = Task { @MainActor in
            await sut.viewModel.completeDueTodayTaskFromNotification(
                taskId: taskId,
                beforeEnqueue: { await gate.suspendAfterPersistence() }
            )
        }
        await gate.waitUntilSuspended()
        let duplicate = Task { @MainActor in
            await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)
        }
        await gate.release()
        let results = await (original.value, duplicate.value)

        XCTAssertEqual(results.0, .failed(.unavailable))
        XCTAssertEqual(results.1, .failed(.unavailable))
        XCTAssertEqual(sut.writeQueue.pendingCount, 0)
        XCTAssertFalse(
            sut.widgetDataManager.loadTaskData(for: .today)
                .optimisticallyCompletedTaskIds.contains(taskId)
        )
    }

    func testConcurrentNotificationCompletionsPreserveBothWidgetUpdates() async {
        let api = TasksViewModelAPIStub()
        let firstTaskId = UUID().uuidString
        let secondTaskId = UUID().uuidString
        let barrier = TasksNotificationCompletionBarrier()
        let sut = makeSUT(api: api, networkAvailable: true)
        sut.widgetDataManager.storeTaskData(
            WidgetTaskData(
                tasks: [],
                totalCount: 2,
                progressCompletedCount: 0,
                progressTotalCount: 2
            ),
            for: .today
        )

        async let firstResult = sut.viewModel.completeDueTodayTaskFromNotification(
            taskId: firstTaskId,
            beforeEnqueue: { await barrier.wait() }
        )
        async let secondResult = sut.viewModel.completeDueTodayTaskFromNotification(
            taskId: secondTaskId,
            beforeEnqueue: { await barrier.wait() }
        )
        let results = await (firstResult, secondResult)

        XCTAssertEqual(results.0, .queued)
        XCTAssertEqual(results.1, .queued)
        await eventually { sut.writeQueue.pendingCount == 2 }
        let snapshot = sut.widgetDataManager.loadTaskData(for: .today)
        XCTAssertEqual(snapshot.totalCount, 0)
        XCTAssertEqual(snapshot.progressCompletedCount, 2)
        XCTAssertEqual(snapshot.progressTotalCount, 2)
        XCTAssertEqual(
            snapshot.optimisticallyCompletedTaskIds,
            [firstTaskId, secondTaskId]
        )
        XCTAssertEqual(
            snapshot.pendingOptimisticCompletionTaskIds,
            [firstTaskId, secondTaskId]
        )
    }

    func testNotificationCompletionStillUpdatesSelectedProjectWidget() async {
        let api = TasksViewModelAPIStub()
        let project = TaskProject(
            id: "project-1",
            title: "Project",
            groupId: nil,
            status: "active",
            updatedAt: nil
        )
        let task = TaskItem(
            id: UUID().uuidString,
            title: "Project task",
            status: "open",
            deadline: TasksUtils.formatDateKey(Date()),
            projectId: project.id
        )
        api.projectTasksResponse = TaskListResponse(
            scope: "project",
            generatedAt: nil,
            tasks: [task],
            projects: [project],
            groups: []
        )
        let sut = makeSUT(api: api, networkAvailable: true)
        let selection = TaskSelection.project(id: project.id)
        await sut.viewModel.load(selection: selection)
        XCTAssertEqual(sut.widgetDataManager.loadTaskData(for: selection).totalCount, 1)

        let result = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: task.id)

        XCTAssertEqual(result, .queued)
        XCTAssertEqual(sut.widgetDataManager.loadTaskData(for: selection).totalCount, 0)
    }

    func testNotificationCompletionQueueFullReturnsFailureWithoutPresentingError() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(
            api: api,
            networkAvailable: false,
            maxPendingWrites: 1
        )
        let queuedTask = TaskItem(id: "queued-task", title: "Queued", status: "open")
        await sut.viewModel.renameTask(task: queuedTask, title: "Already queued")
        await eventually { sut.writeQueue.pendingCount == 1 }
        let taskId = UUID().uuidString
        sut.widgetDataManager.storeTaskData(
            WidgetTaskData(
                tasks: [WidgetTask(id: taskId, title: "Notification task")],
                totalCount: 1,
                progressCompletedCount: 0,
                progressTotalCount: 1
            ),
            for: .today
        )

        let result = await sut.viewModel.completeDueTodayTaskFromNotification(taskId: taskId)

        XCTAssertEqual(result, .failed(.queueFull))
        XCTAssertEqual(sut.writeQueue.pendingCount, 1)
        XCTAssertNil(sut.viewModel.errorMessage)
        XCTAssertNil(sut.toastCenter.toast)
        XCTAssertEqual(sut.widgetDataManager.loadTaskData(for: .today).totalCount, 1)
    }

    func testNotificationCompletionMissingQueueReturnsFailureWithoutPresentingError() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(
            api: api,
            networkAvailable: false,
            attachWriteQueue: false
        )

        let result = await sut.viewModel.completeDueTodayTaskFromNotification(
            taskId: UUID().uuidString
        )

        XCTAssertEqual(result, .failed(.unavailable))
        XCTAssertNil(sut.viewModel.errorMessage)
        XCTAssertNil(sut.toastCenter.toast)
    }

    func testForegroundCompletionQueueFullStillPresentsToast() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(
            api: api,
            networkAvailable: false,
            maxPendingWrites: 1
        )
        let queuedTask = TaskItem(id: "queued-task", title: "Queued", status: "open")
        await sut.viewModel.renameTask(task: queuedTask, title: "Already queued")
        await eventually { sut.writeQueue.pendingCount == 1 }

        let completed = await sut.viewModel.completeTask(
            task: TaskItem(id: "foreground-task", title: "Foreground", status: "open")
        )

        XCTAssertFalse(completed)
        XCTAssertEqual(sut.toastCenter.toast?.message, "Sync queue full. Review pending changes.")
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

    func testLoadProjectSelectionStoresScopedWidgetData() async {
        let api = TasksViewModelAPIStub()
        let group = TaskGroup(id: "g1", title: "Work", updatedAt: nil)
        let project = TaskProject(id: "p1", title: "Launch", groupId: group.id, status: "active", updatedAt: nil)
        let task = TaskItem(
            id: "t1",
            title: "Project task",
            status: "open",
            projectId: project.id,
            groupId: group.id
        )
        api.projectTasksResponse = TaskListResponse(
            scope: "project",
            generatedAt: nil,
            tasks: [task],
            projects: [project],
            groups: [group]
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .project(id: project.id))

        let snapshot = sut.widgetDataManager.loadTaskData(for: .project(id: project.id))
        XCTAssertEqual(snapshot.tasks.map(\.id), ["t1"])
        XCTAssertEqual(snapshot.totalCount, 1)
        XCTAssertEqual(snapshot.tasks.first?.projectName, "Launch")
        XCTAssertEqual(snapshot.tasks.first?.groupName, "Work")
    }

    func testLoadGroupSelectionStoresScopedWidgetData() async {
        let api = TasksViewModelAPIStub()
        let group = TaskGroup(id: "g1", title: "Work", updatedAt: nil)
        let project = TaskProject(id: "p1", title: "Launch", groupId: group.id, status: "active", updatedAt: nil)
        let task = TaskItem(
            id: "t1",
            title: "Group task",
            status: "open",
            projectId: project.id,
            groupId: group.id
        )
        api.groupTasksResponse = TaskListResponse(
            scope: "group",
            generatedAt: nil,
            tasks: [task],
            projects: [project],
            groups: [group]
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .group(id: group.id))

        let snapshot = sut.widgetDataManager.loadTaskData(for: .group(id: group.id))
        XCTAssertEqual(snapshot.tasks.map(\.id), ["t1"])
        XCTAssertEqual(snapshot.totalCount, 1)
        XCTAssertEqual(snapshot.tasks.first?.projectName, "Launch")
        XCTAssertEqual(snapshot.tasks.first?.groupName, "Work")
    }

    func testRefreshWidgetDataSeedsTaskConfigurationCatalogFromTodayResponse() async {
        let api = TasksViewModelAPIStub()
        let group = TaskGroup(id: "group-1", title: "Work", updatedAt: nil)
        let project = TaskProject(
            id: "project-1",
            title: "Launch",
            groupId: group.id,
            status: "active",
            updatedAt: nil
        )
        api.enqueueListResponse(scope: "today", tasks: [], groups: [group], projects: [project])

        let sut = makeSUT(api: api, networkAvailable: true)

        await sut.viewModel.refreshWidgetData()

        let catalog = sut.widgetDataManager.loadTaskConfigurationCatalog()
        XCTAssertEqual(catalog.groups.map(\.title), ["Work"])
        XCTAssertEqual(catalog.projects.map(\.title), ["Launch"])
        XCTAssertEqual(catalog.projects.first?.groupId, group.id)
    }

    // MARK: - Task operations error paths

    func testRenameTaskQueuesWithoutToastPresentation() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Old name", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)

        await sut.viewModel.renameTask(task: task, title: "New name")

        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertEqual(sut.store.tasks.first?.title, "New name")
        XCTAssertNil(sut.viewModel.errorMessage)
        XCTAssertNil(sut.toastCenter.toast)
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testDeleteTaskSuccessRemovesFromStore() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Delete me", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        XCTAssertTrue(sut.store.tasks.contains(where: { $0.id == "t1" }))

        await sut.viewModel.deleteTask(task: task)
        await eventually {
            !sut.store.tasks.contains(where: { $0.id == "t1" })
        }

        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertFalse(sut.store.tasks.contains(where: { $0.id == "t1" }))
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testDeferTaskOffsetsDeadline() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Defer me", status: "open", deadline: "2025-03-15", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)

        await sut.viewModel.deferTask(task: task, days: 3)

        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertEqual(sut.store.tasks.first?.deadline, "2025-03-18")
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testAutosaveNotesQueuesWithoutRefreshingSelectionOrCounts() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Draft", status: "open", notes: "Old", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        XCTAssertEqual(api.listCallCount, 1)
        XCTAssertEqual(api.countsCallCount, 0)

        await sut.viewModel.autosaveNotes(task: task, notes: "Updated")

        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertEqual(api.listCallCount, 1, "Autosave should avoid full list refresh")
        XCTAssertEqual(api.countsCallCount, 0, "Autosave should avoid counts refresh")
        XCTAssertEqual(sut.store.tasks.first?.notes, "Updated")
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testUpdateNotesOptimisticallyUpdatesTaskWithoutRefreshingSelectionOrCounts() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "t1", title: "Draft", status: "open", notes: "Old", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)

        await sut.viewModel.updateNotes(task: task, notes: "Updated")

        await eventually {
            sut.store.tasks.first?.notes == "Updated"
        }
        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertEqual(api.listCallCount, 1, "Manual note save should not force a visible list reload")
        XCTAssertEqual(api.countsCallCount, 0, "Manual note save should not refresh counts")
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testMoveTaskOnlineOptimisticallyUpdatesProjectSelectionBeforeApplyReturns() async {
        let api = TasksViewModelAPIStub()
        let sourceProject = TaskProject(id: "project-1", title: "Inbox", groupId: nil, status: "active", updatedAt: nil)
        let destinationProject = TaskProject(id: "project-2", title: "Later", groupId: nil, status: "active", updatedAt: nil)
        let task = TaskItem(
            id: "task-1",
            title: "Move me",
            status: "open",
            projectId: "project-1",
            updatedAt: "u1"
        )
        api.projectTasksResponse = TaskListResponse(
            scope: "project",
            generatedAt: nil,
            tasks: [task],
            projects: [sourceProject, destinationProject],
            groups: []
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .project(id: "project-1"))
        XCTAssertEqual(sut.viewModel.viewState.sections.first?.tasks.map(\.id), ["task-1"])

        await sut.viewModel.moveTask(task: task, listId: "project-2")

        await eventually {
            sut.viewModel.viewState.sections.flatMap(\.tasks).isEmpty
        }
        XCTAssertEqual(sut.store.tasks.first?.projectId, "project-2")
        XCTAssertEqual(api.applyCallCount, 0)
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    // MARK: - New task creation

    func testCreateTaskOnlineOptimisticallyAddsPreviewWithoutRefreshingList() async {
        let api = TasksViewModelAPIStub()
        api.enqueueListResponse(scope: "today", tasks: [])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        sut.viewModel.startNewTask()

        await sut.viewModel.createTask(title: "Buy milk", notes: "", dueDate: nil, listId: nil)

        await eventually {
            sut.store.tasks.first?.title == "Buy milk"
        }
        XCTAssertEqual(sut.store.tasks.first?.isPreview, true, "Online create should insert a local preview immediately")
        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertEqual(api.listCallCount, 1, "Online create should not reload the list before apply finishes")
        XCTAssertEqual(api.countsCallCount, 0, "Online create should update counts locally instead of refreshing")
        XCTAssertNil(sut.viewModel.newTaskDraft, "Draft should be cleared after success")
        XCTAssertEqual(api.listCallCount, 1, "Successful create should reconcile locally without reloading the list")
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    func testCreateTaskTrimsWhitespaceFromTitle() async {
        let api = TasksViewModelAPIStub()
        api.enqueueListResponse(scope: "today", tasks: [])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        sut.viewModel.startNewTask()

        await sut.viewModel.createTask(title: "  Buy milk  ", notes: "", dueDate: nil, listId: nil)

        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertEqual(sut.store.tasks.first?.title, "Buy milk")
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    // MARK: - Group/project management

    func testCreateGroupOnlineQueuesAndUpdatesPanelState() async {
        let api = TasksViewModelAPIStub()

        let sut = makeSUT(api: api, networkAvailable: true)

        try? await sut.viewModel.createGroup(title: "Work")
        await eventually {
            sut.writeQueue.pendingCount >= 1
                && sut.store.groups.contains(where: { $0.title == "Work" })
        }

        XCTAssertEqual(api.createGroupCallCount, 0)
        XCTAssertEqual(api.countsCallCount, 0)
    }

    func testCreateGroupOfflineQueuesAndUpdatesPanelState() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(api: api, networkAvailable: false)

        try? await sut.viewModel.createGroup(title: "Work")
        await eventually {
            sut.writeQueue.pendingCount >= 1
                && sut.store.groups.contains(where: { $0.title == "Work" })
        }

        XCTAssertEqual(api.createGroupCallCount, 0, "Offline create should not call group endpoint directly")
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
        XCTAssertEqual(api.deleteGroupCallCount, 0)
        await eventually { sut.writeQueue.pendingCount >= 1 }
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
        XCTAssertEqual(api.deleteProjectCallCount, 0)
        await eventually { sut.writeQueue.pendingCount >= 1 }
    }

    // MARK: - Helpers

    private struct SUT {
        let viewModel: TasksViewModel
        let store: TasksStore
        let writeQueue: WriteQueue
        let widgetDataManager: WidgetDataManager
        let toastCenter: ToastCenter
        let accountScopeCoordinator: TaskNotificationAccountScopeCoordinator
    }

    private func makeSUT(
        api: TasksViewModelAPIStub,
        networkAvailable: Bool,
        serverReachable: Bool = true,
        isOffline: Bool = false,
        searchDebounceNanoseconds: UInt64 = 350_000_000,
        maxPendingWrites: Int = 200,
        attachWriteQueue: Bool = true
    ) -> SUT {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let networkStatus = TasksTestNetworkStatus(
            isNetworkAvailable: networkAvailable,
            isServerReachable: serverReachable,
            isOfflineOverride: isOffline
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
            autoProcessEnabled: false,
            maxPendingWrites: maxPendingWrites
        )
        let defaults = UserDefaults(suiteName: "TasksViewModelTests.widget.\(UUID().uuidString)")!
        let widgetDataManager = WidgetDataManager(userDefaults: defaults)
        let toastCenter = ToastCenter()
        let accountScopeCoordinator = TaskNotificationAccountScopeCoordinator()
        _ = accountScopeCoordinator.activate(accountId: UUID().uuidString)
        if attachWriteQueue {
            store.attachWriteQueue(writeQueue)
        }
        let viewModel = TasksViewModel(
            api: api,
            store: store,
            widgetDataManager: widgetDataManager,
            toastCenter: toastCenter,
            networkStatus: networkStatus,
            taskNotificationAccountScopeCoordinator: accountScopeCoordinator,
            searchDebounceNanoseconds: searchDebounceNanoseconds
        )
        return SUT(
            viewModel: viewModel,
            store: store,
            writeQueue: writeQueue,
            widgetDataManager: widgetDataManager,
            toastCenter: toastCenter,
            accountScopeCoordinator: accountScopeCoordinator
        )
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

private actor TasksNotificationCompletionBarrier {
    private var firstWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if let firstWaiter {
            self.firstWaiter = nil
            firstWaiter.resume()
            return
        }
        await withCheckedContinuation { continuation in
            firstWaiter = continuation
        }
    }
}

private actor TasksNotificationEnqueuePersistenceGate {
    private var suspendedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isSuspended = false
    private var isReleased = false

    func suspendAfterPersistence() async {
        isSuspended = true
        suspendedContinuation?.resume()
        suspendedContinuation = nil
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            suspendedContinuation = continuation
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
