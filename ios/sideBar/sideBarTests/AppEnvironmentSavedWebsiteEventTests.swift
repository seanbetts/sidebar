import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
    func testConsumeExtensionEventsWhenActiveEnqueuesSavedWebsiteURL() async {
        let environment = requireEnvironment()
        environment.authState = .active
        let url = "https://example.com/articles/\(UUID().uuidString)"

        storage.extensionEventStore.recordWebsiteSaved(url: url)
        await environment.consumeExtensionEvents()

        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, url)
        XCTAssertTrue(storage.pendingShareStore.loadAll().contains(where: { $0.url == url }))
    }

    func testHandleSignedInActivationConsumesSavedWebsiteURL() async {
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "test-job-id", status: "queued")
            )
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active
        let url = "https://example.com/articles/\(UUID().uuidString)"

        storage.extensionEventStore.recordWebsiteSaved(url: url)

        await environment.handleSignedInActivation(includeDeferredRefresh: false)
        await waitForWebsiteEventSurface(url, in: environment)

        XCTAssertEqual(websitesAPI.lastSavedURL, url)
        XCTAssertTrue(storage.extensionEventStore.consumeEvents().isEmpty)
        XCTAssertTrue(websiteEventIsSurfaced(url, in: environment))
    }

    func testRefreshAuthStateWhenSessionBecomesActiveConsumesSavedWebsiteURL() async {
        let previousSharedEnvironment = AppEnvironment.shared
        defer { AppEnvironment.shared = previousSharedEnvironment }

        let url = "https://example.com/articles/\(UUID().uuidString)"
        let authSession = SavedWebsiteEventMutableAuthSession(authState: .stale)
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "test-job-id", status: "queued")
            )
        )
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            websitesAPI: websitesAPI
        )
        let environment = AppEnvironment(container: container, storage: storage)
        retainedEnvironments.append(environment)
        resetDeepLinkState(environment)
        environment.authState = .stale

        storage.extensionEventStore.recordWebsiteSaved(url: url)

        authSession.authState = .active
        environment.refreshAuthState()
        await waitForWebsiteEventSurface(url, in: environment)

        XCTAssertEqual(websitesAPI.lastSavedURL, url)
        XCTAssertTrue(websiteEventIsSurfaced(url, in: environment))
    }
}

private final class SavedWebsiteEventMutableAuthSession: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    var pendingVerificationEmail: String? {
        nil
    }

    init(authState: AuthState) {
        self.authState = authState
    }

    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String) async throws {}
    func verifyOTP(email: String, code: String) async throws {}
    func signOut() async {}
    func refreshSession() async {}
    func refreshSessionIfStale() async {}
    func sendPasswordReset(email: String) async throws {}
    func updatePassword(_ newPassword: String) async throws {}
}
