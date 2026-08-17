import XCTest
import sideBarShared
@testable import sideBar
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private var didBecomeActiveNotification: Notification.Name {
    #if os(iOS)
    UIApplication.didBecomeActiveNotification
    #else
    NSApplication.didBecomeActiveNotification
    #endif
}

private var didResignActiveNotification: Notification.Name {
    #if os(iOS)
    UIApplication.willResignActiveNotification
    #else
    NSApplication.didResignActiveNotification
    #endif
}

@MainActor
final class ConnectivityMonitorStartupTests: XCTestCase {
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

        XCTAssertFalse(monitor?.isHealthProbeSchedulingEnabled ?? true)
        XCTAssertFalse(monitor?.hasScheduledHealthProbe ?? true)
        XCTAssertEqual(ProbeURLProtocol.completedRequestCount, 0)
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

        XCTAssertFalse(monitor?.isHealthProbeSchedulingEnabled ?? true)
        XCTAssertFalse(monitor?.hasScheduledHealthProbe ?? true)
        XCTAssertEqual(ProbeURLProtocol.completedRequestCount, 0)
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

        XCTAssertFalse(monitor?.isHealthProbeSchedulingEnabled ?? true)
        XCTAssertFalse(monitor?.hasScheduledHealthProbe ?? true)
        XCTAssertEqual(ProbeURLProtocol.completedRequestCount, 0)
        monitor = nil
        session.invalidateAndCancel()
    }

    func testActiveInitializationSchedulesHealthProbes() async {
        let notificationCenter = NotificationCenter()
        let session = makeProbeSession()
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            startMonitoring: true,
            session: session,
            notificationCenter: notificationCenter,
            isAppForegroundActive: { true }
        )

        await waitForMainQueueDrain()

        XCTAssertTrue(monitor?.hasScheduledHealthProbe ?? false)
        monitor = nil
        session.invalidateAndCancel()
    }

    func testInactiveInitializationDoesNotScheduleHealthProbes() async {
        let notificationCenter = NotificationCenter()
        let session = makeProbeSession()
        var isActive = false
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            startMonitoring: true,
            session: session,
            notificationCenter: notificationCenter,
            isAppForegroundActive: { isActive }
        )

        await waitForMainQueueDrain()

        XCTAssertFalse(monitor?.hasScheduledHealthProbe ?? true)
        XCTAssertEqual(ProbeURLProtocol.completedRequestCount, 0)
        monitor = nil
        session.invalidateAndCancel()
    }

    func testActivationRefreshesAndResignationStopsRoutineProbes() async {
        let notificationCenter = NotificationCenter()
        let session = makeProbeSession(expectedProbeRequests: 2)
        var isActive = false
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            startMonitoring: true,
            session: session,
            notificationCenter: notificationCenter,
            isAppForegroundActive: { isActive }
        )

        isActive = true
        notificationCenter.post(name: didBecomeActiveNotification, object: nil)
        await waitForProbeRequests(2)
        XCTAssertTrue(monitor?.hasScheduledHealthProbe ?? false)

        isActive = false
        notificationCenter.post(name: didResignActiveNotification, object: nil)
        await waitForNoScheduledHealthProbes(monitor)

        monitor = nil
        session.invalidateAndCancel()
    }

    func testRepeatedActivationDoesNotDuplicateImmediateRefresh() async {
        let notificationCenter = NotificationCenter()
        let session = makeProbeSession(expectedProbeRequests: 2)
        var isActive = false
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            startMonitoring: true,
            session: session,
            notificationCenter: notificationCenter,
            isAppForegroundActive: { isActive }
        )

        isActive = true
        notificationCenter.post(name: didBecomeActiveNotification, object: nil)
        notificationCenter.post(name: didBecomeActiveNotification, object: nil)
        await waitForProbeRequests(2)

        XCTAssertEqual(ProbeURLProtocol.completedRequestCount, 2)
        XCTAssertTrue(monitor?.hasScheduledHealthProbe ?? false)
        isActive = false
        notificationCenter.post(name: didResignActiveNotification, object: nil)
        await waitForNoScheduledHealthProbes(monitor)
        monitor = nil
        session.invalidateAndCancel()
    }

    func testDeinitializationRemovesActivityObserversAndCancelsTasks() async {
        let notificationCenter = NotificationCenter()
        let session = makeProbeSession()
        var monitor: ConnectivityMonitor? = ConnectivityMonitor(
            baseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            startMonitoring: true,
            session: session,
            notificationCenter: notificationCenter,
            isAppForegroundActive: { true }
        )
        weak var releasedMonitor = monitor

        monitor = nil
        await waitForMainQueueDrain()
        let requestCountAfterDeinit = ProbeURLProtocol.completedRequestCount
        notificationCenter.post(name: didBecomeActiveNotification, object: nil)
        await waitForMainQueueDrain()

        XCTAssertNil(releasedMonitor)
        XCTAssertEqual(ProbeURLProtocol.completedRequestCount, requestCountAfterDeinit)
        session.invalidateAndCancel()
    }

    private func makeProbeSession(expectedProbeRequests: Int = 0) -> URLSession {
        let completionExpectation: XCTestExpectation?
        if expectedProbeRequests > 0 {
            completionExpectation = expectation(description: "Probe requests complete")
            completionExpectation?.expectedFulfillmentCount = expectedProbeRequests
        } else {
            completionExpectation = nil
        }
        ProbeURLProtocol.reset(completionExpectation: completionExpectation)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProbeURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func waitForProbeRequests(_ expectedCount: Int) async {
        guard let completionExpectation = ProbeURLProtocol.completionExpectation else {
            XCTFail("Missing probe request completion expectation")
            return
        }
        await fulfillment(of: [completionExpectation], timeout: 1.0)
        XCTAssertEqual(ProbeURLProtocol.completedRequestCount, expectedCount)
    }

    private func waitForNoScheduledHealthProbes(_ monitor: ConnectivityMonitor?) async {
        guard let monitor else {
            XCTFail("Expected monitor")
            return
        }
        let deadline = Date().addingTimeInterval(1)
        while monitor.hasScheduledHealthProbe, Date() < deadline {
            await Task.yield()
        }
        XCTAssertFalse(monitor.hasScheduledHealthProbe, "Timed out waiting for probe cleanup")
    }

    private func waitForMainQueueDrain() async {
        let expectation = expectation(description: "Drain main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

final class ProbeURLProtocol: URLProtocol {
    private static let recorder = ProbeRecorder()

    static var completedRequestCount: Int {
        recorder.completedRequestCount
    }

    static var completionExpectation: XCTestExpectation? {
        recorder.completionExpectation
    }

    static func reset(completionExpectation: XCTestExpectation? = nil) {
        recorder.reset(completionExpectation: completionExpectation)
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        defer { Self.recorder.recordCompletion() }
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

private final class ProbeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var completedRequests = 0
    private var completionExpectationStorage: XCTestExpectation?

    var completedRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completedRequests
    }

    var completionExpectation: XCTestExpectation? {
        lock.lock()
        defer { lock.unlock() }
        return completionExpectationStorage
    }

    func reset(completionExpectation: XCTestExpectation?) {
        lock.lock()
        completedRequests = 0
        completionExpectationStorage = completionExpectation
        lock.unlock()
    }

    func recordCompletion() {
        lock.lock()
        completedRequests += 1
        let completionExpectation = completionExpectationStorage
        lock.unlock()
        completionExpectation?.fulfill()
    }
}
