import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class TasksViewModelRealtimeTests: XCTestCase {
    func testTaskRealtimeEventsCoalesceIntoSingleRefresh() async {
        let api = TasksViewModelAPIStub()
        let sut = makeSUT(api: api, networkAvailable: true)
        let adapter = BlockingRefreshAdapter(section: .tasks)
        let coordinator = RefreshCoordinator(
            policy: RefreshPolicy(),
            registry: RefreshRegistry(adapters: [adapter])
        )
        let context = RefreshContext(
            visibleSection: .tasks,
            hasVisibleDetail: false,
            pinnedSections: [],
            lastOpenedSection: nil,
            staleTargets: [],
            canAttemptServerRead: true
        )
        sut.viewModel.onRealtimeInvalidation = { change in
            await coordinator.scheduleRealtimeInvalidation(change, context: context)
        }

        let first = Task { await sut.viewModel.applyTaskRealtimeEvent(taskPayload()) }
        let second = Task { await sut.viewModel.applyTaskProjectRealtimeEvent(taskProjectPayload()) }
        let third = Task { await sut.viewModel.applyTaskGroupRealtimeEvent(taskGroupPayload()) }

        await fulfillment(of: [adapter.started], timeout: 1.0)
        XCTAssertEqual(adapter.refreshPlans.map(\.targets), [[.sectionList(.tasks), .taskCounts]])

        adapter.resume()
        _ = await first.value
        _ = await second.value
        _ = await third.value

        XCTAssertEqual(adapter.refreshPlans.count, 1)
        XCTAssertEqual(api.countsCallCount, 0)
        XCTAssertEqual(api.listCallCount, 0)
    }

    func testRefreshAfterExternalTaskChangeRefreshesDirectlyWithoutRealtimeInvalidation() async {
        let api = TasksViewModelAPIStub()
        let initialTask = TaskItem(id: "t1", title: "Before", status: "today", updatedAt: "u1")
        let refreshedTask = TaskItem(id: "t1", title: "After", status: "today", updatedAt: "u2")
        api.enqueueListResponse(scope: "today", tasks: [initialTask], groups: [], projects: [])
        api.enqueueListResponse(scope: "today", tasks: [refreshedTask], groups: [], projects: [])
        api.enqueueListResponse(scope: "today", tasks: [refreshedTask], groups: [], projects: [])

        let sut = makeSUT(api: api, networkAvailable: true)
        var realtimeInvalidationCount = 0
        sut.viewModel.onRealtimeInvalidation = { _ in
            realtimeInvalidationCount += 1
        }
        await sut.viewModel.load(selection: .today)

        await sut.viewModel.refreshAfterExternalTaskChange(force: false)

        XCTAssertEqual(realtimeInvalidationCount, 0)
        XCTAssertEqual(api.countsCallCount, 1)
        XCTAssertEqual(api.listCallCount, 3)
        XCTAssertEqual(sut.viewModel.tasks.first?.title, "Before")
    }

    private func taskPayload() -> RealtimePayload<TaskRealtimeRecord> {
        RealtimePayload(
            eventType: .update,
            table: RealtimeTable.tasks,
            schema: "public",
            record: TaskRealtimeRecord(
                id: "t1",
                title: "After",
                status: "today",
                deadline: nil,
                notes: nil,
                projectId: nil,
                groupId: nil,
                repeating: false,
                repeatTemplate: false,
                recurrenceRule: nil,
                nextInstanceDate: nil,
                updatedAt: "u2",
                deletedAt: nil
            ),
            oldRecord: nil
        )
    }

    private func taskProjectPayload() -> RealtimePayload<TaskProjectRealtimeRecord> {
        RealtimePayload(
            eventType: .update,
            table: RealtimeTable.taskProjects,
            schema: "public",
            record: TaskProjectRealtimeRecord(
                id: "p1",
                title: "Project",
                groupId: nil,
                status: "active",
                updatedAt: "u2",
                deletedAt: nil
            ),
            oldRecord: nil
        )
    }

    private func taskGroupPayload() -> RealtimePayload<TaskGroupRealtimeRecord> {
        RealtimePayload(
            eventType: .update,
            table: RealtimeTable.taskGroups,
            schema: "public",
            record: TaskGroupRealtimeRecord(
                id: "g1",
                title: "Group",
                updatedAt: "u2",
                deletedAt: nil
            ),
            oldRecord: nil
        )
    }

    private struct SUT {
        let viewModel: TasksViewModel
    }

    private func makeSUT(
        api: TasksViewModelAPIStub,
        networkAvailable: Bool,
        serverReachable: Bool = true
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
        let viewModel = TasksViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: networkStatus
        )
        return SUT(viewModel: viewModel)
    }
}

@MainActor
private final class BlockingRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection
    let started = XCTestExpectation(description: "refresh adapter started")
    private(set) var refreshPlans: [RefreshPlan] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(section: AppSection) {
        self.section = section
    }

    func refresh(plan: RefreshPlan) async {
        refreshPlans.append(plan)
        started.fulfill()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
