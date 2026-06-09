import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class TasksViewModelRecurringToastTests: XCTestCase {
    func testCompleteTaskQueuesRecurringCompletionWithoutImmediateScheduleToast() async throws {
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

        let completed = await sut.viewModel.completeTask(task: task)
        let pending = try await sut.writeQueue.fetchPendingWrites()

        XCTAssertTrue(completed)
        XCTAssertEqual(api.applyCallCount, 0)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.operationType, WriteOperation.update.rawValue)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.task.rawValue)
        XCTAssertNil(sut.toastCenter.toast)
    }

    func testCompleteTaskDoesNotScheduleRecurringToastDismissalBeforeSync() async {
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
        for _ in 0..<5 {
            await Task.yield()
        }

        XCTAssertNil(sut.toastCenter.toast)
        XCTAssertEqual(sleepProbe.requestedNanoseconds, [])
    }

    private struct SUT {
        let viewModel: TasksViewModel
        let toastCenter: ToastCenter
        let writeQueue: WriteQueue
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
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: ConnectivityMonitor(
                baseUrl: URL(string: "http://localhost")!,
                startMonitoring: false
            ),
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)
        let toastCenter = ToastCenter(sleep: toastSleep)
        let viewModel = TasksViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: networkStatus
        )
        return SUT(viewModel: viewModel, toastCenter: toastCenter, writeQueue: writeQueue)
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
