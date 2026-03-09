import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class TasksViewModelRealtimeTests: XCTestCase {
    func testTaskRealtimeEventsCoalesceIntoSingleRefresh() async {
        let api = TasksViewModelAPIStub()
        let initialTask = TaskItem(id: "t1", title: "Before", status: "today", updatedAt: "u1")
        let refreshedTask = TaskItem(id: "t1", title: "After", status: "today", updatedAt: "u2")
        api.enqueueListResponse(scope: "today", tasks: [initialTask], groups: [], projects: [])
        api.enqueueListResponse(scope: "today", tasks: [refreshedTask], groups: [], projects: [])
        api.enqueueListResponse(scope: "today", tasks: [refreshedTask], groups: [], projects: [])

        let sut = makeSUT(
            api: api,
            networkAvailable: true,
            realtimeRefreshDelayNanoseconds: 0
        )
        await sut.viewModel.load(selection: .today)

        let taskPayload = RealtimePayload(
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
        let taskProjectPayload = RealtimePayload(
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
        let taskGroupPayload = RealtimePayload(
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

        await sut.viewModel.applyTaskRealtimeEvent(taskPayload)
        await sut.viewModel.applyTaskProjectRealtimeEvent(taskProjectPayload)
        await sut.viewModel.applyTaskGroupRealtimeEvent(taskGroupPayload)

        await eventually {
            api.countsCallCount == 1 && api.listCallCount == 3
        }

        XCTAssertEqual(api.countsCallCount, 1)
        XCTAssertEqual(api.listCallCount, 3)
        XCTAssertEqual(sut.store.tasks.first?.title, "After")
    }

    private struct SUT {
        let viewModel: TasksViewModel
        let store: TasksStore
    }

    private func makeSUT(
        api: TasksViewModelAPIStub,
        networkAvailable: Bool,
        serverReachable: Bool = true,
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
        let viewModel = TasksViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: networkStatus,
            realtimeRefreshDelayNanoseconds: realtimeRefreshDelayNanoseconds
        )
        return SUT(viewModel: viewModel, store: store)
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
