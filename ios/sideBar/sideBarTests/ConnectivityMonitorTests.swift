import XCTest
import Combine
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

    func testLifecycleFailureRecordingRespectsAppForegroundState() async {
        struct Scenario {
            let signal: RequestLifecycleSignal
            let isActive: Bool
            let expectedSignals: [RequestLifecycleSignal]
            let expectedServerReachable: Bool
        }
        let readFailure = RequestLifecycleSignal(
            operation: "get.files",
            requestKind: .foregroundRead,
            stage: .failed,
            errorCategory: .timeout
        )
        let backgroundMutation = RequestLifecycleSignal(
            operation: "patch.tasks",
            requestKind: .foregroundMutation,
            stage: .failed,
            errorCategory: .timeout
        )
        let scenarios = [
            Scenario(
                signal: readFailure,
                isActive: false,
                expectedSignals: [],
                expectedServerReachable: false
            ),
            Scenario(
                signal: readFailure,
                isActive: true,
                expectedSignals: [readFailure],
                expectedServerReachable: false
            ),
            Scenario(
                signal: backgroundMutation,
                isActive: false,
                expectedSignals: [backgroundMutation],
                expectedServerReachable: false
            )
        ]

        for scenario in scenarios {
            let notificationCenter = NotificationCenter()
            var recordedSignals: [RequestLifecycleSignal] = []
            var monitor: ConnectivityMonitor? = ConnectivityMonitor(
                baseUrl: URL(string: "http://localhost")!,
                startMonitoring: false,
                notificationCenter: notificationCenter,
                isAppForegroundActive: { scenario.isActive },
                requestLifecycleFailureRecorder: { recordedSignals.append($0) }
            )
            guard let strongMonitor = monitor else {
                XCTFail("Expected monitor")
                return
            }

            notificationCenter.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["signal": scenario.signal]
            )
            await waitForMainQueueDrain()
            notificationCenter.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["signal": scenario.signal]
            )
            await waitForMainQueueDrain()

            XCTAssertEqual(recordedSignals, scenario.expectedSignals + scenario.expectedSignals)
            XCTAssertEqual(strongMonitor.isServerReachable, scenario.expectedServerReachable)
            monitor = nil
        }
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

    func testServerReachabilityControlsServerReadAvailability() async {
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        guard let strongMonitor = monitor else {
            XCTFail("Expected monitor")
            return
        }

        XCTAssertTrue(strongMonitor.canAttemptServerRead)

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

        XCTAssertFalse(strongMonitor.canAttemptServerRead)

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

}
extension ConnectivityMonitorTests {
    func testInactiveLifecycleFailuresUpdateStateWithoutSchedulingProbe() async {
        let notificationCenter = NotificationCenter()
        var recordedSignals: [RequestLifecycleSignal] = []
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: true,
            notificationCenter: notificationCenter,
            isAppForegroundActive: { false },
            requestLifecycleFailureRecorder: { recordedSignals.append($0) }
        )
        let signal = RequestLifecycleSignal(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            stage: .failed,
            errorCategory: .timeout
        )
        for _ in 0..<2 {
            notificationCenter.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["signal": signal, "error": URLError(.timedOut)]
            )
        }
        await waitForMainQueueDrain()
        XCTAssertFalse(monitor?.isServerReachable ?? true)
        XCTAssertFalse(monitor?.hasScheduledHealthProbe ?? true)
        XCTAssertTrue(recordedSignals.isEmpty)
        monitor = nil
    }

    func testInactiveLifecycleSuccessesRecoverStateWithoutSchedulingProbe() async {
        let notificationCenter = NotificationCenter()
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: true,
            notificationCenter: notificationCenter,
            isAppForegroundActive: { false }
        )
        let failure = RequestLifecycleSignal(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            stage: .failed,
            errorCategory: .timeout
        )
        let success = RequestLifecycleSignal(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            stage: .succeeded
        )
        for _ in 0..<2 {
            notificationCenter.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["signal": failure, "error": URLError(.timedOut)]
            )
        }
        await waitForMainQueueDrain()
        XCTAssertFalse(monitor?.isServerReachable ?? true)
        for _ in 0..<2 {
            notificationCenter.post(
                name: .apiClientRequestSucceeded,
                object: nil,
                userInfo: ["signal": success]
            )
        }
        await waitForMainQueueDrain()
        XCTAssertTrue(monitor?.isServerReachable ?? false)
        XCTAssertFalse(monitor?.hasScheduledHealthProbe ?? true)
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
        XCTAssertEqual(ProbeURLProtocol.completedRequestCount, 2)

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
