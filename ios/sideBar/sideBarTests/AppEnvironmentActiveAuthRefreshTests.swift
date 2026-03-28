import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
    func testRefreshAuthStateWhenSessionBecomesActiveLoadsWebsiteListWhileQueuedReplayIsInFlight() async {
        let previousSharedEnvironment = AppEnvironment.shared
        defer { AppEnvironment.shared = previousSharedEnvironment }

        let authSession = ActiveAuthRefreshMutableAuthSession(authState: .stale)
        let replayGate = AsyncReplayGate()
        let queuedURL = "https://example.com/articles/\(UUID().uuidString)"
        let existingItem = WebsiteItem(
            id: "website-existing",
            title: "Existing Website",
            url: "https://example.com/already-saved",
            domain: "example.com",
            savedAt: "2026-03-17T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-03-17T00:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "test-job-id", status: "queued")
            ),
            listResult: .success(WebsitesResponse(items: [existingItem], archivedCount: 0)),
            onSave: { _ in
                await replayGate.wait()
            }
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

        storage.extensionEventStore.recordWebsiteSaved(url: queuedURL)

        authSession.authState = .active
        environment.refreshAuthState()

        for _ in 0..<40 where environment.websitesViewModel.items.first?.url != existingItem.url {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(environment.authState, .active)
        XCTAssertEqual(environment.websitesViewModel.items.first?.url, existingItem.url)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, queuedURL)
        XCTAssertEqual(websitesAPI.saveCallCount, 1)

        await replayGate.open()
        await waitForWebsiteEventSurface(queuedURL, in: environment)
    }
}

private final class ActiveAuthRefreshMutableAuthSession: AuthSession {
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

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        authState = .active
    }

    func signUp(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func verifyOTP(email: String, code: String) async throws {
        _ = email
        _ = code
    }

    func refreshSession() async {}

    func refreshSessionIfStale() async {}

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }
}
