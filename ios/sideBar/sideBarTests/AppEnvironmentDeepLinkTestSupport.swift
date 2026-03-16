import Foundation
import XCTest
import sideBarShared
@testable import sideBar

final class DeepLinkWebsitesAPI: WebsitesProviding {
    let saveResult: Result<WebsiteSaveResponse, Error>
    let detailResult: Result<WebsiteDetail, Error>
    let listResult: Result<WebsitesResponse, Error>
    let onSave: ((String) async -> Void)?
    private(set) var lastSavedURL: String?
    private(set) var listCallCount = 0

    init(
        saveResult: Result<WebsiteSaveResponse, Error>,
        listResult: Result<WebsitesResponse, Error> = .success(
            WebsitesResponse(items: [], archivedCount: 0)
        ),
        detailResult: Result<WebsiteDetail, Error> = .failure(DeepLinkWebsitesAPIError.forced),
        onSave: ((String) async -> Void)? = nil
    ) {
        self.saveResult = saveResult
        self.listResult = listResult
        self.detailResult = detailResult
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

    func save(url: String) async throws -> WebsiteSaveResponse {
        lastSavedURL = url
        await onSave?(url)
        return try saveResult.get()
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

@MainActor
extension AppEnvironmentDeepLinkTests {
    func clearWidgetPendingOperations() {
        _ = storage.widgetDataManager.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
        _ = storage.widgetDataManager.consumePendingOperations(for: .notes, actionType: NoteWidgetAction.self)
        _ = storage.widgetDataManager.consumePendingQuickSave()
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

    func makeEnvironment(
        storage: AppEnvironmentStorage,
        websitesAPI: (any WebsitesProviding)? = nil
    ) -> AppEnvironment {
        let authSession = PlaceholderAuthSession(authState: .signedOut)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            websitesAPI: websitesAPI
        )
        let environment = AppEnvironment(container: container, storage: storage)
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
