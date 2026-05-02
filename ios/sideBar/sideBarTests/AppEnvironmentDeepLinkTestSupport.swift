import Foundation
import XCTest
import sideBarShared
@testable import sideBar

final class DeepLinkWebsitesAPI: WebsitesProviding {
    let saveResult: Result<WebsiteSaveJobResponse, Error>
    let detailResult: Result<WebsiteDetail, Error>
    let listResult: Result<WebsitesResponse, Error>
    let cancelResult: Result<Void, Error>
    private let jobStatusResult: Result<WebsiteJobStatusResponse, Error>
    let onSave: ((String) async -> Void)?
    private(set) var lastSavedURL: String?
    private(set) var saveCallCount = 0
    private(set) var listCallCount = 0
    private(set) var canceledJobIds: [String] = []

    init(
        saveResult: Result<WebsiteSaveJobResponse, Error>,
        listResult: Result<WebsitesResponse, Error> = .success(
            WebsitesResponse(items: [], archivedCount: 0)
        ),
        detailResult: Result<WebsiteDetail, Error> = .failure(DeepLinkWebsitesAPIError.forced),
        jobStatusResult: Result<WebsiteJobStatusResponse, Error> = .failure(DeepLinkWebsitesAPIError.forced),
        cancelResult: Result<Void, Error> = .failure(DeepLinkWebsitesAPIError.forced),
        onSave: ((String) async -> Void)? = nil
    ) {
        self.saveResult = saveResult
        self.listResult = listResult
        self.detailResult = detailResult
        self.jobStatusResult = jobStatusResult
        self.cancelResult = cancelResult
        self.onSave = onSave
    }

    func list() async throws -> WebsitesResponse {
        listCallCount += 1
        return try listResult.get()
    }

    func listArchived(limit: Int, offset: Int) async throws -> WebsitesResponse {
        _ = limit
        _ = offset
        return WebsitesResponse(items: [], archivedCount: 0)
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        return try detailResult.get()
    }

    func save(url: String) async throws -> WebsiteSaveJobResponse {
        saveCallCount += 1
        lastSavedURL = url
        await onSave?(url)
        return try saveResult.get()
    }

    func jobStatus(id: String) async throws -> WebsiteJobStatusResponse {
        _ = id
        return try jobStatusResult.get()
    }

    func cancel(jobId: String) async throws {
        canceledJobIds.append(jobId)
        try cancelResult.get()
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        throw DeepLinkWebsitesAPIError.forced
    }

    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        _ = clientUpdatedAt
        throw DeepLinkWebsitesAPIError.forced
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = title
        _ = clientUpdatedAt
        throw DeepLinkWebsitesAPIError.forced
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = archived
        _ = clientUpdatedAt
        throw DeepLinkWebsitesAPIError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
        throw DeepLinkWebsitesAPIError.forced
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
        throw DeepLinkWebsitesAPIError.forced
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        throw DeepLinkWebsitesAPIError.forced
    }
}

private enum DeepLinkWebsitesAPIError: Error {
    case forced
}

private enum NoNetworkAppEnvironmentError: Error {
    case unused
}

private struct NoNetworkNotesAPI: NotesProviding {
    func listTree() async throws -> FileTree { FileTree(children: []) }
    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return FileTree(children: [])
    }
    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw NoNetworkAppEnvironmentError.unused
    }
    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }
    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        _ = id
        _ = document
        throw NoNetworkAppEnvironmentError.unused
    }
    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw NoNetworkAppEnvironmentError.unused
    }
    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        throw NoNetworkAppEnvironmentError.unused
    }
    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw NoNetworkAppEnvironmentError.unused
    }
    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw NoNetworkAppEnvironmentError.unused
    }
    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw NoNetworkAppEnvironmentError.unused
    }
    func updatePinnedOrder(ids: [String]) async throws { _ = ids }
    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw NoNetworkAppEnvironmentError.unused
    }
    func createFolder(path: String) async throws { _ = path }
    func renameFolder(oldPath: String, newName: String) async throws {
        _ = oldPath
        _ = newName
    }
    func moveFolder(oldPath: String, newParent: String) async throws {
        _ = oldPath
        _ = newParent
    }
    func deleteFolder(path: String) async throws { _ = path }
}

private final class NoNetworkTasksAPI: TasksProviding {
    func list(scope: String) async throws -> TaskListResponse {
        TaskListResponse(scope: scope, generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }
    func projectTasks(projectId: String) async throws -> TaskListResponse {
        _ = projectId
        return TaskListResponse(scope: "project", generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }
    func groupTasks(groupId: String) async throws -> TaskListResponse {
        _ = groupId
        return TaskListResponse(scope: "group", generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }
    func search(query: String) async throws -> TaskListResponse {
        _ = query
        return TaskListResponse(scope: "search", generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }
    func counts() async throws -> TaskCountsResponse {
        TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 0, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )
    }
    func createGroup(title: String) async throws -> TaskGroup {
        _ = title
        throw NoNetworkAppEnvironmentError.unused
    }
    func renameGroup(groupId: String, title: String) async throws -> TaskGroup {
        _ = groupId
        _ = title
        throw NoNetworkAppEnvironmentError.unused
    }
    func deleteGroup(groupId: String) async throws {
        _ = groupId
        throw NoNetworkAppEnvironmentError.unused
    }
    func createProject(title: String, groupId: String?) async throws -> TaskProject {
        _ = title
        _ = groupId
        throw NoNetworkAppEnvironmentError.unused
    }
    func renameProject(projectId: String, title: String) async throws -> TaskProject {
        _ = projectId
        _ = title
        throw NoNetworkAppEnvironmentError.unused
    }
    func deleteProject(projectId: String) async throws {
        _ = projectId
        throw NoNetworkAppEnvironmentError.unused
    }
    func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse {
        _ = payload
        return TaskSyncResponse(
            applied: [],
            tasks: [],
            nextTasks: [],
            conflicts: [],
            updates: nil,
            serverUpdatedSince: nil
        )
    }
    func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse {
        _ = payload
        return TaskSyncResponse(
            applied: [],
            tasks: [],
            nextTasks: [],
            conflicts: [],
            updates: nil,
            serverUpdatedSince: nil
        )
    }
}

private func makeNoNetworkWebsitesAPI() -> any WebsitesProviding {
    DeepLinkWebsitesAPI(
        saveResult: .success(
            WebsiteSaveJobResponse(jobId: "job-\(UUID().uuidString)", status: "queued")
        )
    )
}

func makeNoNetworkServiceContainer(
    authSession: AuthSession,
    cacheClient: CacheClient,
    websitesAPI: (any WebsitesProviding)? = nil
) -> ServiceContainer {
    ServiceContainer(
        config: .fallbackForTesting(),
        authSession: authSession,
        cacheClient: cacheClient,
        notesAPI: NoNetworkNotesAPI(),
        ingestionAPI: IngestionStoreTestsSupport.MockIngestionAPI(
            listResponse: IngestionListResponse(items: [])
        ),
        tasksAPI: NoNetworkTasksAPI(),
        websitesAPI: websitesAPI ?? makeNoNetworkWebsitesAPI()
    )
}

@MainActor
extension AppEnvironmentDeepLinkTests {
    func clearWidgetPendingOperations() {
        _ = storage.widgetDataManager.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
        _ = storage.widgetDataManager.consumePendingOperations(for: .notes, actionType: NoteWidgetAction.self)
    }

    func clearExtensionEvents() {
        _ = storage.extensionEventStore.consumeEvents()
        storage.pendingShareStore.replaceAll([])
    }

    func websiteEventIsSurfaced(_ url: String, in environment: AppEnvironment) -> Bool {
        if environment.websitesViewModel.pendingWebsite?.url == url {
            return true
        }
        if environment.websitesViewModel.store.active?.url == url {
            return true
        }
        if storage.pendingShareStore.loadAll().contains(where: { $0.url == url }) {
            return true
        }
        return environment.websitesViewModel.items.contains(where: { $0.url == url })
    }

    func waitForWebsiteEventSurface(_ url: String, in environment: AppEnvironment, attempts: Int = 40) async {
        for _ in 0..<attempts where !websiteEventIsSurfaced(url, in: environment) {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func waitForPendingWebsite(_ url: String, in environment: AppEnvironment, attempts: Int = 40) async {
        for _ in 0..<attempts where environment.websitesViewModel.pendingWebsite?.url != url {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func waitForWebsiteSaveCallCount(
        _ expectedCount: Int,
        in websitesAPI: DeepLinkWebsitesAPI,
        attempts: Int = 40
    ) async {
        for _ in 0..<attempts where websitesAPI.saveCallCount < expectedCount {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func waitForCompletion(_ completion: AsyncCompletionFlag, attempts: Int = 40) async -> Bool {
        for _ in 0..<attempts {
            if await completion.finished() {
                return true
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await completion.finished()
    }

    func waitForSavedWebsite(
        id: String,
        url: String,
        in environment: AppEnvironment,
        attempts: Int = 40
    ) async {
        for _ in 0..<attempts where !savedWebsiteIsSurfaced(id: id, url: url, in: environment) {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func savedWebsiteIsSurfaced(id: String, url: String, in environment: AppEnvironment) -> Bool {
        guard environment.websitesViewModel.items.first?.id == id else { return false }
        guard environment.websitesViewModel.items.first?.url == url else { return false }
        return environment.websitesStore.hasCachedDetail(id: id)
    }

    func forceTasksOffline(in environment: AppEnvironment, attempts: Int = 20) async {
        let error = URLError(.notConnectedToInternet)
        for _ in 0..<2 {
            NotificationCenter.default.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["error": error]
            )
        }

        guard let monitor = environment.tasksViewModel.networkStatus as? ConnectivityMonitor else {
            XCTFail("Expected connectivity monitor-backed task network status")
            return
        }

        for _ in 0..<attempts where monitor.isNetworkAvailable || monitor.isServerReachable {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func makeEnvironment(
        storage: AppEnvironmentStorage,
        authSession: AuthSession = PlaceholderAuthSession(authState: .signedOut),
        websitesAPI: (any WebsitesProviding)? = nil,
        refreshCoordinator: RefreshCoordinatorType? = nil
    ) -> AppEnvironment {
        let container = makeNoNetworkServiceContainer(
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            websitesAPI: websitesAPI
        )
        let environment = AppEnvironment(
            container: container,
            storage: storage,
            refreshCoordinator: refreshCoordinator
        )
        retainedEnvironments.append(environment)
        return environment
    }

    func requireEnvironment(
        storage: AppEnvironmentStorage? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AppEnvironment {
        guard let environment else {
            XCTFail("Expected test environment", file: file, line: line)
            return AppEnvironment.shared!
        }
        if let storage, environment.storage.userDefaults != storage.userDefaults {
            XCTFail("Expected environment storage to match test storage", file: file, line: line)
        }
        return environment
    }

    func resetDeepLinkState(_ environment: AppEnvironment) {
        environment.authState = .signedOut
        environment.isMacSettingsPresented = false
        environment.commandSelection = nil
        environment.focusedSection = nil
        environment.isTasksFocused = false
        environment.pendingNewTaskDeepLink = false
        environment.pendingNewNoteDeepLink = false
        environment.pendingScratchpadDeepLink = false
        environment.tasksPhoneDetailRouteId = nil
        environment.tasksViewModel.cancelNewTask()
        environment.tasksViewModel.reset()
        environment.chatViewModel.reset()
        environment.websitesViewModel.pendingWebsite = nil
    }
}
