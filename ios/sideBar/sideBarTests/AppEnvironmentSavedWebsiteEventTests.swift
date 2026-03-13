import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
    func testConsumeExtensionEventsWhenActiveAppliesSavedWebsiteDetail() async {
        let environment = requireEnvironment()
        environment.authState = .active
        let website = makeSavedWebsiteEvent(url: "https://example.com/articles/\(UUID().uuidString)")

        storage.extensionEventStore.recordWebsiteSaved(website: website)
        await environment.consumeExtensionEvents()

        XCTAssertNil(environment.websitesViewModel.pendingWebsite)
        XCTAssertEqual(environment.websitesViewModel.items.first?.id, website.id)
        XCTAssertEqual(environment.websitesViewModel.items.first?.url, website.url)
        XCTAssertTrue(environment.websitesStore.hasCachedDetail(id: website.id))
    }

    func testConsumeExtensionEventsWhenActivePreservesYouTubeTranscriptMetadata() async {
        let environment = requireEnvironment()
        environment.authState = .active
        let videoId = "abc123xyzAA"
        let website = ExtensionSavedWebsite(
            id: "website-\(UUID().uuidString)",
            title: "Saved Video",
            url: "https://www.youtube.com/watch?v=\(videoId)",
            urlFull: "https://www.youtube.com/watch?v=\(videoId)",
            domain: "youtube.com",
            content: "Saved transcript content",
            source: "youtube",
            savedAt: "2026-03-13T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: [
                videoId: WebsiteTranscriptEntry(
                    status: "ready",
                    fileId: "file-1",
                    updatedAt: "2026-03-13T00:00:00Z",
                    error: nil
                )
            ],
            readingTime: "12 min",
            updatedAt: "2026-03-13T00:00:00Z",
            lastOpenedAt: nil
        )

        storage.extensionEventStore.recordWebsiteSaved(website: website)
        await environment.consumeExtensionEvents()
        try? await environment.websitesStore.loadDetail(id: website.id)

        XCTAssertEqual(
            environment.websitesViewModel.items.first?.youtubeTranscripts?[videoId]?.status,
            "ready"
        )
        XCTAssertEqual(
            environment.websitesStore.active?.youtubeTranscripts?[videoId]?.fileId,
            "file-1"
        )
    }

    func testExtensionEventStoreCompactsOversizedSavedWebsitePayload() {
        let hugeContent = String(repeating: "x", count: 300_000)
        let website = ExtensionSavedWebsite(
            id: "website-\(UUID().uuidString)",
            title: "Huge Website",
            url: "https://example.com/huge",
            urlFull: "https://example.com/huge",
            domain: "example.com",
            content: hugeContent,
            source: "web",
            savedAt: "2026-03-13T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: "40 min",
            updatedAt: "2026-03-13T00:00:00Z",
            lastOpenedAt: nil
        )

        storage.extensionEventStore.recordWebsiteSaved(website: website)
        let events = storage.extensionEventStore.consumeEvents()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.website?.id, website.id)
        XCTAssertNil(events.first?.website?.content)
        XCTAssertEqual(events.first?.website?.requiresDetailFetch, true)
    }

    func testExtensionEventStoreFallsBackToMinimalWebsiteEventWhenCompactPayloadStillExceedsLimit() {
        let oversizedTitle = String(repeating: "T", count: 300_000)
        let website = ExtensionSavedWebsite(
            id: "website-\(UUID().uuidString)",
            title: oversizedTitle,
            url: "https://example.com/huge",
            urlFull: "https://example.com/huge",
            domain: "example.com",
            content: "Saved content",
            source: "web",
            savedAt: "2026-03-13T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: "40 min",
            updatedAt: "2026-03-13T00:00:00Z",
            lastOpenedAt: nil
        )

        storage.extensionEventStore.recordWebsiteSaved(website: website)
        let events = storage.extensionEventStore.consumeEvents()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.websiteUrl, website.url)
        XCTAssertEqual(events.first?.website?.id, website.id)
        XCTAssertEqual(events.first?.website?.url, website.url)
        XCTAssertEqual(events.first?.website?.domain, website.domain)
        XCTAssertNil(events.first?.website?.content)
        XCTAssertEqual(events.first?.website?.requiresDetailFetch, true)
        XCTAssertEqual(events.first?.website?.title.count, 256)
    }

    func testConsumeExtensionEventsWhenSavedWebsitePayloadRequiresDetailFetchHydratesByID() async {
        let detail = WebsiteDetail(
            id: "website-\(UUID().uuidString)",
            title: "Fetched Detail",
            url: "https://example.com/fetched",
            urlFull: "https://example.com/fetched",
            domain: "example.com",
            content: "Fetched content",
            source: "web",
            savedAt: "2026-03-13T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: "6 min",
            updatedAt: "2026-03-13T00:00:00Z",
            lastOpenedAt: nil
        )
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .failure(NSError(domain: "AppEnvironmentSavedWebsiteEventTests", code: 1)),
            detailResult: .success(detail)
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active
        let website = ExtensionSavedWebsite(
            id: detail.id,
            title: detail.title,
            url: detail.url,
            urlFull: detail.urlFull,
            domain: detail.domain,
            content: nil,
            source: detail.source,
            savedAt: detail.savedAt,
            publishedAt: detail.publishedAt,
            pinned: detail.pinned,
            pinnedOrder: detail.pinnedOrder,
            archived: detail.archived,
            faviconUrl: detail.faviconUrl,
            faviconR2Key: detail.faviconR2Key,
            youtubeTranscripts: detail.youtubeTranscripts,
            readingTime: detail.readingTime,
            updatedAt: detail.updatedAt,
            lastOpenedAt: detail.lastOpenedAt,
            requiresDetailFetch: true
        )

        storage.extensionEventStore.recordWebsiteSaved(website: website)
        await environment.consumeExtensionEvents()

        XCTAssertTrue(environment.websitesStore.hasCachedDetail(id: detail.id))
        try? await environment.websitesStore.loadDetail(id: detail.id)
        XCTAssertEqual(environment.websitesStore.active?.content, "Fetched content")
    }

    func testHandleSignedInActivationConsumesSavedWebsiteDetailEvent() async {
        let environment = requireEnvironment()
        environment.authState = .active
        let website = makeSavedWebsiteEvent(url: "https://example.com/articles/\(UUID().uuidString)")

        storage.extensionEventStore.recordWebsiteSaved(website: website)

        await environment.handleSignedInActivation()

        XCTAssertEqual(environment.websitesViewModel.items.first?.id, website.id)
        XCTAssertTrue(environment.websitesStore.hasCachedDetail(id: website.id))
        XCTAssertTrue(storage.extensionEventStore.consumeEvents().isEmpty)
    }

    func testRefreshAuthStateWhenSessionBecomesActiveAppliesSavedWebsiteDetailEvents() async {
        let previousSharedEnvironment = AppEnvironment.shared
        defer { AppEnvironment.shared = previousSharedEnvironment }

        let authSession = SavedWebsiteEventMutableAuthSession(authState: .stale)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container, storage: storage)
        retainedEnvironments.append(environment)
        resetDeepLinkState(environment)
        environment.authState = .stale

        let website = makeSavedWebsiteEvent(url: "https://example.com/articles/\(UUID().uuidString)")
        storage.extensionEventStore.recordWebsiteSaved(website: website)

        authSession.authState = .active
        environment.refreshAuthState()

        await waitForWebsiteEventSurface(website.url, in: environment)

        XCTAssertEqual(environment.authState, AuthState.active)
        XCTAssertEqual(environment.websitesViewModel.items.first?.id, website.id)
        XCTAssertTrue(environment.websitesStore.hasCachedDetail(id: website.id))
    }

    func makeSavedWebsiteEvent(url: String) -> ExtensionSavedWebsite {
        ExtensionSavedWebsite(
            id: "website-\(UUID().uuidString)",
            title: "Saved Website",
            url: url,
            urlFull: url,
            domain: "example.com",
            content: "Saved content",
            source: "web",
            savedAt: "2026-03-13T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: "4 min",
            updatedAt: "2026-03-13T00:00:00Z",
            lastOpenedAt: nil,
            requiresDetailFetch: false
        )
    }
}

private final class SavedWebsiteEventMutableAuthSession: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    init(authState: AuthState) {
        self.authState = authState
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        authState = .active
    }

    func refreshSession() async {}

    func refreshSessionIfStale() async {}

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }
}
