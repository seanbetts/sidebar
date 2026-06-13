import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentDependencyBuilderTests: XCTestCase {
    private static let sharedContainer = ServiceContainer(
        config: .fallbackForTesting(),
        authSession: PlaceholderAuthSession(),
        cacheClient: TestCacheClient()
    )
    private static var retainedDependencies: [AppEnvironment.EnvironmentDependencies] = []

    func testBuildDependenciesWiresStoreWriteQueuesAndSpotlightIndexer() {
        let dependencies = makeDependencies()

        XCTAssertTrue(dependencies.notesStore.writeQueue === dependencies.writeQueue)
        XCTAssertTrue(dependencies.tasksStore.writeQueue === dependencies.writeQueue)
        XCTAssertTrue(dependencies.websitesStore.writeQueue === dependencies.writeQueue)
        XCTAssertTrue(dependencies.ingestionStore.writeQueue === dependencies.writeQueue)

        XCTAssertTrue((dependencies.notesStore.spotlightIndexer as AnyObject?) === dependencies.spotlightIndexer)
        XCTAssertTrue((dependencies.tasksStore.spotlightIndexer as AnyObject?) === dependencies.spotlightIndexer)
        XCTAssertTrue((dependencies.websitesStore.spotlightIndexer as AnyObject?) === dependencies.spotlightIndexer)
        XCTAssertTrue((dependencies.ingestionStore.spotlightIndexer as AnyObject?) === dependencies.spotlightIndexer)
    }

    func testBuildDependenciesUsesNoOpSpotlightIndexerInTestMode() {
        let dependencies = makeDependencies()

        XCTAssertTrue(dependencies.spotlightIndexer is NoOpSpotlightIndexer)
    }

    func testBuildDependenciesReusesOfflineStoreAcrossFeatureStores() {
        let dependencies = makeDependencies()

        XCTAssertTrue(dependencies.notesStore.offlineStore === dependencies.offlineStore)
        XCTAssertTrue(dependencies.websitesStore.offlineStore === dependencies.offlineStore)
        XCTAssertTrue(dependencies.ingestionStore.offlineStore === dependencies.offlineStore)
        XCTAssertTrue(dependencies.settingsStore.offlineStore === dependencies.offlineStore)
        XCTAssertTrue(dependencies.settingsViewModel.settingsStore === dependencies.settingsStore)
        XCTAssertTrue(dependencies.settingsStore.writeQueue === dependencies.writeQueue)
    }

    func testDependenciesExposeAppleIntelligenceFoundations() {
        let container = Self.sharedContainer

        XCTAssertNotNil(container.appleIntelligenceAvailabilityProvider)
        XCTAssertNotNil(container.languageModelService)
        XCTAssertNotNil(container.speechTranscriptionService)
        XCTAssertNotNil(container.intelligenceDiagnosticsRecorder)

        let environment = AppEnvironment(
            container: container,
            storage: AppEnvironmentStorage(
                userDefaults: UserDefaults(
                    suiteName: "AppEnvironmentDependencyBuilderTests.aiWork.\(UUID().uuidString)"
                )!
            )
        )
        let id = UUID()
        let snapshot = AIWorkSnapshot(
            id: id,
            capability: .liveNotes,
            status: .completed,
            routeMetadata: nil,
            payload: Data("local-ai-work".utf8),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        environment.aiWorkLocalStore.save(snapshot)

        XCTAssertEqual(
            environment.offlineStore.get(
                key: CacheKeys.aiWork(capability: .liveNotes, id: id),
                as: AIWorkSnapshot.self
            ),
            snapshot
        )
    }

    func testBuildDependenciesCreateIsolatedOfflineStoresPerTestEnvironment() {
        let firstDependencies = makeDependencies()
        let secondDependencies = makeDependencies()

        firstDependencies.offlineStore.set(
            key: "isolation-check",
            entityType: "note",
            value: ["title": "First environment snapshot"],
            lastSyncAt: nil
        )

        let secondSnapshot = secondDependencies.offlineStore.get(
            key: "isolation-check",
            as: [String: String].self
        )

        XCTAssertNil(secondSnapshot)
    }

    func testOrderedWorkspaceContextSectionsPrioritizeFocusedPane() {
        let state = WorkspaceState(
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.notes)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .builtIn(.files)),
            sidebarSelection: .files,
            activeSection: .files,
            focusedSection: .files
        )

        let ordered = AppEnvironment.ViewModelDependencyBuilder.orderedWorkspaceContextSections(
            workspaceState: state
        )

        XCTAssertEqual(
            ordered,
            [
                .init(pane: .secondary, section: .files),
                .init(pane: .primary, section: .notes)
            ]
        )
    }

    func testOrderedWorkspaceContextSectionsUsePrimaryOnlyInCompactLayout() {
        let state = WorkspaceState(
            layout: .compact,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.websites)),
            secondaryPane: nil,
            sidebarSelection: .websites,
            activeSection: .websites,
            focusedSection: .websites
        )

        let ordered = AppEnvironment.ViewModelDependencyBuilder.orderedWorkspaceContextSections(
            workspaceState: state
        )

        XCTAssertEqual(ordered, [.init(pane: .primary, section: .websites)])
    }

    func testSettingsRequestUserIdPrefersAuthorizedTokenSubjectOverCachedUserId() {
        let session = FakeAuthSession(
            accessToken: makeJwt(sub: "token-user"),
            userId: "cached-user",
            authState: .active
        )

        let resolved = AppEnvironment.ViewModelDependencyBuilder.settingsRequestUserId(
            authSession: session,
            requireAuthorization: false
        )

        XCTAssertEqual(resolved, "token-user")
    }

    func testSettingsRequestUserIdRequiresAuthorizationWhenRequested() {
        let session = FakeAuthSession(
            accessToken: nil,
            userId: "cached-user",
            authState: .staleRecoverable
        )

        let resolved = AppEnvironment.ViewModelDependencyBuilder.settingsRequestUserId(
            authSession: session,
            requireAuthorization: true
        )

        XCTAssertNil(resolved)
    }

    func testRequestContextIncludesOnlyVisibleWorkspaceSections() {
        var workspaceState = WorkspaceState(
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.websites)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .builtIn(.chat)),
            sidebarSelection: .websites,
            activeSection: .websites,
            focusedSection: .websites
        )
        let dependencies = makeDependencies(
            workspaceStateProvider: { workspaceState }
        )

        dependencies.websitesViewModel.selectedWebsiteId = "website-1"
        dependencies.websitesViewModel.active = makeWebsiteDetail(id: "website-1")
        dependencies.ingestionViewModel.selectedFileId = "file-1"
        dependencies.ingestionViewModel.activeMeta = makeIngestionMeta(fileId: "file-1")

        let firstContext = dependencies.chatViewModel.requestContextProvider?()
        let firstOpenContext = firstContext?.openContext ?? [:]
        XCTAssertNotNil(firstOpenContext["website"])
        XCTAssertNil(firstOpenContext["file"])

        workspaceState = WorkspaceState(
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.chat)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .builtIn(.files)),
            sidebarSelection: .files,
            activeSection: .files,
            focusedSection: .files
        )

        let secondContext = dependencies.chatViewModel.requestContextProvider?()
        let secondOpenContext = secondContext?.openContext ?? [:]
        XCTAssertNil(secondOpenContext["website"])
        XCTAssertNotNil(secondOpenContext["file"])
    }

    private func makeDependencies(
        workspaceStateProvider: @escaping () -> WorkspaceState? = { nil }
    ) -> AppEnvironment.EnvironmentDependencies {
        let dependencies = AppEnvironment.buildDependencies(
            container: Self.sharedContainer,
            isTestMode: true,
            widgetDataManager: WidgetDataManager(
                userDefaults: UserDefaults(
                    suiteName: "AppEnvironmentDependencyBuilderTests.\(UUID().uuidString)"
                )!
            ),
            workspaceStateProvider: workspaceStateProvider
        )
        Self.retainedDependencies.append(dependencies)
        return dependencies
    }

    private func makeWebsiteDetail(id: String) -> WebsiteDetail {
        WebsiteDetail(
            id: id,
            title: "Example",
            url: "https://example.com",
            urlFull: "https://example.com",
            domain: "example.com",
            content: "content",
            source: "manual",
            savedAt: "2026-02-28T12:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: nil,
            lastOpenedAt: nil
        )
    }

    private func makeIngestionMeta(fileId: String) -> IngestionMetaResponse {
        IngestionMetaResponse(
            file: IngestedFileMeta(
                id: fileId,
                filenameOriginal: "example.pdf",
                path: nil,
                mimeOriginal: "application/pdf",
                sizeBytes: 128,
                sha256: nil,
                pinned: nil,
                pinnedOrder: nil,
                category: "document",
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-02-28T12:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "ready",
                stage: "done",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: 1.0,
                attempts: 1,
                updatedAt: "2026-02-28T12:00:00Z"
            ),
            derivatives: [],
            recommendedViewer: nil
        )
    }

    private func makeJwt(sub: String) -> String {
        let header = Data("{\"alg\":\"none\",\"typ\":\"JWT\"}".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let payload = Data("{\"sub\":\"\(sub)\",\"exp\":4102444800}".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(payload)."
    }
}

private final class FakeAuthSession: AuthSession {
    let accessToken: String?
    let userId: String?
    let authState: AuthState

    init(
        accessToken: String? = nil,
        userId: String? = nil,
        authState: AuthState
    ) {
        self.accessToken = accessToken
        self.userId = userId
        self.authState = authState
    }

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    var pendingVerificationEmail: String? {
        nil
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func signUp(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func verifyOTP(email: String, code: String) async throws {
        _ = email
        _ = code
    }

    func refreshSession() async {
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
    }
}
