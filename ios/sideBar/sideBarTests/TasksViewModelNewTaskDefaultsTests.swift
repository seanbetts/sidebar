import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class TasksViewModelNewTaskDefaultsTests: XCTestCase {
    func testStartNewTaskDefaultsDueDateToTodayForTodaySelection() async {
        let api = TasksViewModelAPIStub()
        api.enqueueListResponse(scope: "today", tasks: [])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .today)
        sut.viewModel.startNewTask()

        let draft = sut.viewModel.newTaskDraft
        XCTAssertNotNil(draft)
        XCTAssertNotNil(draft?.dueDate)
        XCTAssertTrue(
            draft?.dueDate.map { Calendar.current.isDate($0, inSameDayAs: Date()) } ?? false
        )
    }

    func testStartNewTaskDefaultsDueDateToTomorrowForUpcomingSelection() async {
        let api = TasksViewModelAPIStub()
        api.enqueueListResponse(scope: "upcoming", tasks: [])

        let sut = makeSUT(api: api, networkAvailable: true)
        await sut.viewModel.load(selection: .upcoming)
        sut.viewModel.startNewTask()

        let draft = sut.viewModel.newTaskDraft
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        XCTAssertNotNil(draft)
        XCTAssertNotNil(draft?.dueDate)
        XCTAssertTrue(
            draft?.dueDate.map { Calendar.current.isDate($0, inSameDayAs: tomorrow) } ?? false
        )
    }

    private struct SUT {
        let viewModel: TasksViewModel
    }

    private func makeSUT(api: TasksViewModelAPIStub, networkAvailable: Bool) -> SUT {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let networkStatus = TasksTestNetworkStatus(
            isNetworkAvailable: networkAvailable,
            isServerReachable: true
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
            networkStatus: networkStatus
        )
        return SUT(viewModel: viewModel)
    }
}
