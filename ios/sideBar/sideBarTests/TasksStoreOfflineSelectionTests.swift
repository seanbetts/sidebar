import Foundation
import XCTest
@testable import sideBar

@MainActor
final class TasksStoreOfflineSelectionTests: XCTestCase {
    func testLoadOfflineUnavailableSelectionDoesNotEnterLoadingStateOrFetch() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = OfflineSelectionStubTasksAPI()
        let networkStatus = OfflineSelectionTestNetworkStatus(isNetworkAvailable: false)
        let store = TasksStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: networkStatus
        )

        await store.load(selection: .upcoming)

        XCTAssertEqual(store.selection, .upcoming)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.tasks, [])
        XCTAssertEqual(store.errorMessage, "This task list isn't available offline yet.")
        XCTAssertEqual(api.listCallCount, 0)
    }
}

@MainActor
private final class OfflineSelectionTestNetworkStatus: NetworkStatusProviding {
    var isNetworkAvailable: Bool
    var isServerReachable: Bool
    var isOffline: Bool

    init(isNetworkAvailable: Bool, isOffline: Bool = false, isServerReachable: Bool = true) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isOffline = isOffline
        self.isServerReachable = isServerReachable
    }
}

@MainActor
private final class OfflineSelectionStubTasksAPI: TasksProviding {
    private(set) var listCallCount = 0

    func list(scope: String) async throws -> TaskListResponse {
        _ = scope
        listCallCount += 1
        return TaskListResponse(scope: "unused", generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }

    func projectTasks(projectId: String) async throws -> TaskListResponse {
        _ = projectId
        throw OfflineSelectionStubError.unused
    }

    func groupTasks(groupId: String) async throws -> TaskListResponse {
        _ = groupId
        throw OfflineSelectionStubError.unused
    }

    func search(query: String) async throws -> TaskListResponse {
        _ = query
        throw OfflineSelectionStubError.unused
    }

    func counts() async throws -> TaskCountsResponse {
        throw OfflineSelectionStubError.unused
    }

    func createGroup(title: String) async throws -> TaskGroup {
        _ = title
        throw OfflineSelectionStubError.unused
    }

    func renameGroup(groupId: String, title: String) async throws -> TaskGroup {
        _ = groupId
        _ = title
        throw OfflineSelectionStubError.unused
    }

    func deleteGroup(groupId: String) async throws {
        _ = groupId
        throw OfflineSelectionStubError.unused
    }

    func createProject(title: String, groupId: String?) async throws -> TaskProject {
        _ = title
        _ = groupId
        throw OfflineSelectionStubError.unused
    }

    func renameProject(projectId: String, title: String) async throws -> TaskProject {
        _ = projectId
        _ = title
        throw OfflineSelectionStubError.unused
    }

    func deleteProject(projectId: String) async throws {
        _ = projectId
        throw OfflineSelectionStubError.unused
    }

    func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse {
        _ = payload
        throw OfflineSelectionStubError.unused
    }

    func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse {
        _ = payload
        throw OfflineSelectionStubError.unused
    }
}

private enum OfflineSelectionStubError: Error {
    case unused
}
