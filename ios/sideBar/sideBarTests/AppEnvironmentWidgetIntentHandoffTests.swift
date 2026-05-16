import XCTest
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
    func testSignedOutTaskDeepLinkQueuesUntilAuthentication() async {
        let environment = requireEnvironment()
        environment.authState = .signedOut

        environment.handleDeepLink(URL(string: "sidebar://tasks/new")!)

        XCTAssertNil(environment.commandSelection)
        XCTAssertNil(environment.pendingSidebarDeepLink)
        XCTAssertEqual(environment.queuedProtectedDeepLinks.count, 1)

        environment.authState = .active
        await environment.replayProtectedDeferredActionsIfReady()

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertEqual(environment.pendingSidebarDeepLink, URL(string: "sidebar://tasks/new")!)
        XCTAssertTrue(environment.queuedProtectedDeepLinks.isEmpty)
    }

    func testSignedOutNoteDeepLinkQueuesUntilAuthentication() async {
        let environment = requireEnvironment()
        environment.authState = .signedOut

        environment.handleDeepLink(URL(string: "sidebar://notes/new")!)

        XCTAssertNil(environment.commandSelection)
        XCTAssertNil(environment.pendingSidebarDeepLink)
        XCTAssertEqual(environment.queuedProtectedDeepLinks.count, 1)

        environment.authState = .active
        await environment.replayProtectedDeferredActionsIfReady()

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertEqual(environment.pendingSidebarDeepLink, URL(string: "sidebar://notes/new")!)
        XCTAssertTrue(environment.queuedProtectedDeepLinks.isEmpty)
    }

    func testSignedOutWebsiteSaveDeepLinkQueuesUntilAuthentication() async {
        let savedURL = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "test-job-id", status: "queued")
            )
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .signedOut

        environment.handleDeepLink(Self.queuedQuickSaveDeepLink(url: savedURL))

        XCTAssertNil(environment.commandSelection)
        XCTAssertTrue(environment.queuedProtectedDeepLinks.contains(Self.queuedQuickSaveDeepLink(url: savedURL)))

        environment.authState = .active
        await environment.replayProtectedDeferredActionsIfReady()
        await waitForWebsiteEventSurface(savedURL, in: environment)

        XCTAssertEqual(environment.commandSelection, .websites)
        XCTAssertEqual(websitesAPI.lastSavedURL, savedURL)
        XCTAssertTrue(websiteEventIsSurfaced(savedURL, in: environment))
        XCTAssertTrue(environment.queuedProtectedDeepLinks.isEmpty)
    }

    private static func queuedQuickSaveDeepLink(url: String) -> URL {
        var components = URLComponents()
        components.scheme = "sidebar"
        components.host = "websites"
        components.path = "/save"
        components.queryItems = [
            URLQueryItem(name: "url", value: url)
        ]
        return components.url!
    }
}
