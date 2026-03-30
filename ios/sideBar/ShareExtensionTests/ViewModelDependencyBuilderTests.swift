import XCTest
@testable import sideBar

final class ViewModelDependencyBuilderTests: XCTestCase {
    func testCurrentLocationProviderUsesNoOpProviderInTestMode() {
        let provider = AppEnvironment.ViewModelDependencyBuilder.makeCurrentLocationProvider(
            isTestMode: true
        )

        XCTAssertTrue(provider is NoOpCurrentLocationProvider)
    }

    func testCurrentLocationLabelResolverUsesNoOpResolverInTestMode() {
        let resolver = AppEnvironment.ViewModelDependencyBuilder.makeCurrentLocationLabelResolver(
            isTestMode: true
        )

        XCTAssertTrue(resolver is NoOpCurrentLocationLabelResolver)
    }
}
