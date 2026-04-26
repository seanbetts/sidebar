import XCTest
@testable import sideBar

final class AppEnvironmentWebsiteQueueStartupTests: XCTestCase {
    func testQueuedWebsiteReconciliationRequiresActiveAuth() {
        XCTAssertFalse(
            AppEnvironment.shouldReconcileQueuedWebsitesOnItemsChange(authState: .signedOut)
        )
        XCTAssertFalse(
            AppEnvironment.shouldReconcileQueuedWebsitesOnItemsChange(authState: .staleRecoverable)
        )
        XCTAssertTrue(
            AppEnvironment.shouldReconcileQueuedWebsitesOnItemsChange(authState: .active)
        )
    }

    func testConnectivityRecoveryRequiresActualOfflineTransition() {
        XCTAssertFalse(
            AppEnvironment.shouldNotifyWebsiteQueueConnectivityRecovery(
                previousIsOffline: nil,
                currentIsOffline: false
            )
        )
        XCTAssertFalse(
            AppEnvironment.shouldNotifyWebsiteQueueConnectivityRecovery(
                previousIsOffline: false,
                currentIsOffline: false
            )
        )
        XCTAssertFalse(
            AppEnvironment.shouldNotifyWebsiteQueueConnectivityRecovery(
                previousIsOffline: nil,
                currentIsOffline: true
            )
        )
        XCTAssertFalse(
            AppEnvironment.shouldNotifyWebsiteQueueConnectivityRecovery(
                previousIsOffline: false,
                currentIsOffline: true
            )
        )
        XCTAssertTrue(
            AppEnvironment.shouldNotifyWebsiteQueueConnectivityRecovery(
                previousIsOffline: true,
                currentIsOffline: false
            )
        )
    }

    func testMacWindowlessWebsiteQueueBootstrapRequiresActiveAuth() {
        XCTAssertFalse(
            AppEnvironment.shouldBootstrapMacWindowlessWebsiteQueueHost(authState: .signedOut)
        )
        XCTAssertFalse(
            AppEnvironment.shouldBootstrapMacWindowlessWebsiteQueueHost(authState: .staleRecoverable)
        )
        XCTAssertTrue(
            AppEnvironment.shouldBootstrapMacWindowlessWebsiteQueueHost(authState: .active)
        )
    }
}
