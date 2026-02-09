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

    func testBuildDependenciesReusesOfflineStoreAcrossFeatureStores() {
        let dependencies = makeDependencies()

        XCTAssertTrue(dependencies.notesStore.offlineStore === dependencies.offlineStore)
        XCTAssertTrue(dependencies.websitesStore.offlineStore === dependencies.offlineStore)
        XCTAssertTrue(dependencies.ingestionStore.offlineStore === dependencies.offlineStore)
    }

    private func makeDependencies() -> AppEnvironment.EnvironmentDependencies {
        let dependencies = AppEnvironment.buildDependencies(
            container: Self.sharedContainer,
            isTestMode: true
        )
        Self.retainedDependencies.append(dependencies)
        return dependencies
    }
}
