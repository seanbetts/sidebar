import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class TasksViewModelRecurringToastTests: XCTestCase {
    func testCompleteTaskSuccessShowsRecurringScheduleSuccessToastWithDate() async {
        let expectedDate = TasksUtils.tasksDateFormatter
            .date(from: "2026-03-04")?
            .formatted(.dateTime.day().month(.wide))
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
            "Weekly review next scheduled for \(expectedDate ?? "March 4")"
        )
        if case .success? = sut.toastCenter.toast?.style {
            // expected
        } else {
            XCTFail("Expected recurring completion toast style to be success")
        }
    }

    func testCompleteTaskSuccessKeepsRecurringScheduleToastVisiblePastThreeSeconds() async {
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

        let sleepProbe = ToastDismissSleepProbe()
        let sut = makeSUT(api: api, networkAvailable: true, toastSleep: sleepProbe.sleep(nanoseconds:))
        await sut.viewModel.load(selection: .today)

        await sut.viewModel.completeTask(task: task)
        await eventually {
            sut.toastCenter.toast != nil
        }
        await eventually {
            sleepProbe.requestedNanoseconds == [4_000_000_000]
        }

        XCTAssertNotNil(sut.toastCenter.toast)
        XCTAssertEqual(sleepProbe.requestedNanoseconds, [4_000_000_000])
        sleepProbe.completeSleeps()
    }

    private struct SUT {
        let viewModel: TasksViewModel
        let toastCenter: ToastCenter
    }

    private func makeSUT(
        api: TasksViewModelAPIStub,
        networkAvailable: Bool,
        serverReachable: Bool = true,
        toastSleep: @escaping @MainActor (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
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
        let toastCenter = ToastCenter(sleep: toastSleep)
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
        pollNanoseconds: UInt64 = 0,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let isSatisfied = condition()
            if isSatisfied {
                return
            }
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

@MainActor
private final class ToastDismissSleepProbe {
    private(set) var requestedNanoseconds: [UInt64] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(nanoseconds: UInt64) async {
        requestedNanoseconds.append(nanoseconds)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func completeSleeps() {
        let continuations = self.continuations
        self.continuations = []
        for continuation in continuations {
            continuation.resume()
        }
    }
}
