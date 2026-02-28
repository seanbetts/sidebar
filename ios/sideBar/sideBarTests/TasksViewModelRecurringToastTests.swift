import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class TasksViewModelRecurringToastTests: XCTestCase {
    func testCompleteTaskSuccessShowsRecurringScheduleSuccessToastWithDate() async {
        let api = TasksViewModelAPIStub()
        let task = TaskItem(id: "task-1", title: "Weekly review", status: "open", updatedAt: "u1")
        api.enqueueListResponse(scope: "today", tasks: [task])
        api.enqueueListResponse(scope: "today", tasks: [])
        api.applyResult = .success(
            TaskSyncResponse(
                applied: ["op-1"],
                tasks: [],
                nextTasks: [
                    TaskItem(
                        id: "task-2",
                        title: "Weekly review",
                        status: "open",
                        deadline: "2026-03-04",
                        updatedAt: "u2"
                    )
                ],
                conflicts: [],
                updates: nil,
                serverUpdatedSince: nil
            )
        )

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)

        await sut.viewModel.completeTask(task: task)
        await eventually {
            sut.toastCenter.toast != nil
        }

        XCTAssertEqual(
            sut.toastCenter.toast?.message,
            "Next instance scheduled for 2026-03-04: \"Weekly review\""
        )
        if case .success? = sut.toastCenter.toast?.style {
            // expected
        } else {
            XCTFail("Expected recurring completion toast style to be success")
        }
    }

    private struct SUT {
        let viewModel: TasksViewModel
        let toastCenter: ToastCenter
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
        let toastCenter = ToastCenter()
        let viewModel = TasksViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: networkStatus
        )
        return SUT(viewModel: viewModel, toastCenter: toastCenter)
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
