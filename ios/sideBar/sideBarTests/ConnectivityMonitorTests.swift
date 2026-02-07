import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ConnectivityMonitorTests: XCTestCase {
    func testCannotConnectToHostOnlyMarksServerUnreachable() async {
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        guard let strongMonitor = monitor else {
            XCTFail("Expected monitor")
            return
        }

        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.cannotConnectToHost)]
        )
        await waitForMainQueueDrain()
        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.cannotConnectToHost)]
        )

        XCTAssertTrue(strongMonitor.isNetworkAvailable)
        XCTAssertFalse(strongMonitor.isOffline)
        XCTAssertFalse(strongMonitor.isServerReachable)

        // Ensure observers are released before the next test.
        monitor = nil
    }

    func testNotConnectedToInternetMarksOfflineAfterThreshold() async {
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        guard let strongMonitor = monitor else {
            XCTFail("Expected monitor")
            return
        }

        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.notConnectedToInternet)]
        )
        await waitForMainQueueDrain()
        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.notConnectedToInternet)]
        )

        XCTAssertFalse(strongMonitor.isNetworkAvailable)
        XCTAssertTrue(strongMonitor.isOffline)
        XCTAssertFalse(strongMonitor.isServerReachable)

        monitor = nil
    }

    func testTwoRequestSuccessesRecoverNetworkAndServerState() async {
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        guard let strongMonitor = monitor else {
            XCTFail("Expected monitor")
            return
        }

        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.notConnectedToInternet)]
        )
        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.notConnectedToInternet)]
        )
        await waitForMainQueueDrain()
        XCTAssertTrue(strongMonitor.isOffline)

        NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)
        NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)
        await waitForMainQueueDrain()

        XCTAssertTrue(strongMonitor.isNetworkAvailable)
        XCTAssertFalse(strongMonitor.isOffline)
        XCTAssertTrue(strongMonitor.isServerReachable)

        monitor = nil
    }

    private func waitForMainQueueDrain() async {
        let expectation = expectation(description: "Drain main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
