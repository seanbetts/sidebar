import XCTest
@testable import sideBar

@MainActor
final class ConnectivityMonitorTests: XCTestCase {
    func testCannotConnectToHostOnlyMarksServerUnreachable() {
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        guard let monitor else {
            XCTFail("Expected monitor")
            return
        }

        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.cannotConnectToHost)]
        )
        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.cannotConnectToHost)]
        )

        XCTAssertTrue(monitor.isNetworkAvailable)
        XCTAssertFalse(monitor.isOffline)
        XCTAssertFalse(monitor.isServerReachable)

        // Ensure observers are released before the next test.
        monitor = nil
    }

    func testNotConnectedToInternetMarksOfflineAfterThreshold() {
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        guard let monitor else {
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

        XCTAssertFalse(monitor.isNetworkAvailable)
        XCTAssertTrue(monitor.isOffline)
        XCTAssertFalse(monitor.isServerReachable)

        monitor = nil
    }

    func testTwoRequestSuccessesRecoverNetworkAndServerState() {
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        guard let monitor else {
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
        XCTAssertTrue(monitor.isOffline)

        NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)
        NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)

        XCTAssertTrue(monitor.isNetworkAvailable)
        XCTAssertFalse(monitor.isOffline)
        XCTAssertTrue(monitor.isServerReachable)

        monitor = nil
    }
}
