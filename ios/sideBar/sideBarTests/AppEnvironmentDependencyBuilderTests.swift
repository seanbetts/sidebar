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
}
