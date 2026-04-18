import XCTest
import Combine
import sideBarShared
@testable import sideBar

@MainActor
final class ConnectivityMonitorTests: XCTestCase {
    func testDefaultInitializerDoesNotStartMonitoringUnderXCTest() async {
        ProbeURLProtocol.reset()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ProbeURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)

        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            session: session
        )
        XCTAssertNotNil(monitor)

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(ProbeURLProtocol.requestCount, 0)
        monitor = nil
        session.invalidateAndCancel()
    }

    func testStartMonitoringFalseDoesNotScheduleBackgroundHealthProbes() async {
        ProbeURLProtocol.reset()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ProbeURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)

        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            startMonitoring: false,
            session: session
        )
        XCTAssertNotNil(monitor)

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(ProbeURLProtocol.requestCount, 0)
        monitor = nil
        session.invalidateAndCancel()
    }

    func testStartMonitoringFalseDoesNotProbeAfterRequestFailureNotifications() async {
        ProbeURLProtocol.reset()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ProbeURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)

        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            startMonitoring: false,
            session: session
        )
        XCTAssertNotNil(monitor)

        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.cannotConnectToHost)]
        )
        await waitForMainQueueDrain()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(ProbeURLProtocol.requestCount, 0)
        monitor = nil
        session.invalidateAndCancel()
    }

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
        await waitForMainQueueDrain()

        XCTAssertTrue(strongMonitor.isNetworkAvailable)
        XCTAssertFalse(strongMonitor.isOffline)
        XCTAssertFalse(strongMonitor.isServerReachable)

        // Ensure observers are released before the next test.
        monitor = nil
    }

    func testServerBusyLifecycleSignalMarksServerUnreachableAfterThreshold() async {
        let notificationCenter = NotificationCenter()
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false,
            notificationCenter: notificationCenter
        )
        guard let strongMonitor = monitor else {
            XCTFail("Expected monitor")
            return
        }

        let signal = RequestLifecycleSignal(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            stage: .failed,
            errorCategory: .serverBusy
        )

        notificationCenter.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["signal": signal]
        )
        await waitForMainQueueDrain()
        notificationCenter.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["signal": signal]
        )
        await waitForMainQueueDrain()

        XCTAssertTrue(strongMonitor.isNetworkAvailable)
        XCTAssertFalse(strongMonitor.isOffline)
        XCTAssertFalse(strongMonitor.isServerReachable)

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
        await waitForMainQueueDrain()

        XCTAssertFalse(strongMonitor.isNetworkAvailable)
        XCTAssertTrue(strongMonitor.isOffline)
        XCTAssertFalse(strongMonitor.isServerReachable)

        monitor = nil
    }

    func testOfflineLifecycleSignalMarksOfflineAfterThreshold() async {
        let notificationCenter = NotificationCenter()
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false,
            notificationCenter: notificationCenter
        )
        guard let strongMonitor = monitor else {
            XCTFail("Expected monitor")
            return
        }

        let signal = RequestLifecycleSignal(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            stage: .failed,
            errorCategory: .offline
        )

        notificationCenter.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["signal": signal]
        )
        await waitForMainQueueDrain()
        notificationCenter.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["signal": signal]
        )
        await waitForMainQueueDrain()

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

    func testTimeoutOnlyMarksServerUnreachable() async {
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
            userInfo: ["error": URLError(.timedOut)]
        )
        await waitForMainQueueDrain()
        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.timedOut)]
        )
        await waitForMainQueueDrain()

        XCTAssertTrue(strongMonitor.isNetworkAvailable)
        XCTAssertFalse(strongMonitor.isOffline)
        XCTAssertFalse(strongMonitor.isServerReachable)

        monitor = nil
    }

    func testSecureConnectionFailureOnlyMarksServerUnreachable() async {
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
            userInfo: ["error": URLError(.secureConnectionFailed)]
        )
        await waitForMainQueueDrain()
        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.secureConnectionFailed)]
        )
        await waitForMainQueueDrain()

        XCTAssertTrue(strongMonitor.isNetworkAvailable)
        XCTAssertFalse(strongMonitor.isOffline)
        XCTAssertFalse(strongMonitor.isServerReachable)

        monitor = nil
    }

    func testRepeatedSuccessNotificationsDoNotRepublishUnchangedOnlineState() async {
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        guard let strongMonitor = monitor else {
            XCTFail("Expected monitor")
            return
        }

        var publishCount = 0
        var cancellables = Set<AnyCancellable>()
        strongMonitor.objectWillChange
            .sink {
                publishCount += 1
            }
            .store(in: &cancellables)

        NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)
        NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)
        await waitForMainQueueDrain()

        XCTAssertTrue(strongMonitor.isNetworkAvailable)
        XCTAssertFalse(strongMonitor.isOffline)
        XCTAssertTrue(strongMonitor.isServerReachable)
        XCTAssertEqual(
            publishCount,
            0,
            "Repeated success notifications should not republish unchanged online state."
        )

        cancellables.removeAll()
        monitor = nil
    }

    func testManualRefreshStatusImmediatelyRecoversOfflineStateWhenProbesSucceed() async {
        ProbeURLProtocol.reset()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ProbeURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)

        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            startMonitoring: false,
            session: session
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

        await strongMonitor.refreshStatusNow()

        XCTAssertTrue(strongMonitor.isNetworkAvailable)
        XCTAssertFalse(strongMonitor.isOffline)
        XCTAssertTrue(strongMonitor.isServerReachable)
        XCTAssertEqual(ProbeURLProtocol.requestCount, 2)

        monitor = nil
        session.invalidateAndCancel()
    }

    private func waitForMainQueueDrain() async {
        let expectation = expectation(description: "Drain main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

private final class ProbeURLProtocol: URLProtocol {
    static var requestCount = 0

    static func reset() {
        requestCount = 0
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
