import XCTest
import sideBarShared
@testable import sideBar

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

    private func waitForMainQueueDrain() async {
        let expectation = expectation(description: "Drain main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

final class ProbeURLProtocol: URLProtocol {
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
