import Foundation
import XCTest
@testable import sideBar

@MainActor
final class TasksStoreTestNetworkStatus: NetworkStatusProviding {
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
final class TasksStoreStubTasksAPI: TasksProviding {
    var listCallCount: Int = 0
    var countsCallCount: Int = 0
    var listResponsesByScope: [String: TaskListResponse] = [:]
    var listErrorsByScope: [String: Error] = [:]
    var listResponseDelaysByScope: [String: UInt64] = [:]
    var searchResponse = TaskListResponse(scope: "search", generatedAt: nil, tasks: [], projects: nil, groups: nil)
    var countsResponseDelayNanoseconds: UInt64 = 0
    var suspendCounts = false
    private var suspendedListContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var suspendedListScopes: Set<String> = []
    private var suspendedCountsContinuation: CheckedContinuation<Void, Never>?
    var countsResponse = TaskCountsResponse(
        generatedAt: nil,
        counts: TaskCounts(today: 0, upcoming: 0, completed: 0),
        projects: [],
        groups: []
    )

    func suspendList(scope: String) {
        suspendedListScopes.insert(scope)
    }

    func resumeList(scope: String) {
        suspendedListContinuations.removeValue(forKey: scope)?.resume()
    }

    func resumeCounts() {
        suspendedCountsContinuation?.resume()
        suspendedCountsContinuation = nil
    }

    func list(scope: String) async throws -> TaskListResponse {
        listCallCount += 1
        if let error = listErrorsByScope[scope] {
            throw error
        }
        if let delay = listResponseDelaysByScope[scope], delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        if suspendedListScopes.remove(scope) != nil {
            await withCheckedContinuation { continuation in
                suspendedListContinuations[scope] = continuation
            }
        }
        return listResponsesByScope[scope]
            ?? TaskListResponse(scope: scope, generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }

    func projectTasks(projectId: String) async throws -> TaskListResponse {
        throw TasksStoreStubError.unused
    }

    func groupTasks(groupId: String) async throws -> TaskListResponse {
        throw TasksStoreStubError.unused
    }

    func search(query: String) async throws -> TaskListResponse {
        _ = query
        return searchResponse
    }

    func counts() async throws -> TaskCountsResponse {
        countsCallCount += 1
        if countsResponseDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: countsResponseDelayNanoseconds)
        }
        if suspendCounts {
            suspendCounts = false
            await withCheckedContinuation { continuation in
                suspendedCountsContinuation = continuation
            }
        }
        return countsResponse
    }

    func createGroup(title: String) async throws -> TaskGroup {
        throw TasksStoreStubError.unused
    }

    func renameGroup(groupId: String, title: String) async throws -> TaskGroup {
        throw TasksStoreStubError.unused
    }

    func deleteGroup(groupId: String) async throws {
        throw TasksStoreStubError.unused
    }

    func createProject(title: String, groupId: String?) async throws -> TaskProject {
        throw TasksStoreStubError.unused
    }

    func renameProject(projectId: String, title: String) async throws -> TaskProject {
        throw TasksStoreStubError.unused
    }

    func deleteProject(projectId: String) async throws {
        throw TasksStoreStubError.unused
    }

    func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse {
        throw TasksStoreStubError.unused
    }

    func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse {
        throw TasksStoreStubError.unused
    }
}

enum TasksStoreStubError: Error {
    case unused
}

@MainActor
func waitUntilTasksCondition(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
    let timeoutNanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
    let start = DispatchTime.now().uptimeNanoseconds

    while !condition() {
        if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
            XCTFail("Timed out waiting for condition")
            return
        }
        await Task.yield()
    }
}
