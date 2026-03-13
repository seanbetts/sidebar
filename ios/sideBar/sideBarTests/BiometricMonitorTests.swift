import XCTest
import LocalAuthentication
@testable import sideBar

@MainActor
final class BiometricMonitorTests: XCTestCase {
    func testStartMonitoringPerformsInitialRefreshAndActiveRefresh() async {
        let center = NotificationCenter()
        var statuses: [(Bool, LABiometryType)] = [
            (false, .none),
            (true, .touchID)
        ]
        let refreshExpectation = expectation(description: "refreshes after active notification")
        let monitor = BiometricMonitor(
            notificationCenter: center,
            activeNotificationName: .biometricMonitorDidBecomeActiveForTests,
            statusProvider: {
                let nextStatus = statuses.removeFirst()
                if statuses.isEmpty {
                    refreshExpectation.fulfill()
                }
                return nextStatus
            }
        )

        monitor.startMonitoring()
        XCTAssertFalse(monitor.isAvailable)
        XCTAssertEqual(monitor.biometryType, LABiometryType.none)

        center.post(name: .biometricMonitorDidBecomeActiveForTests, object: nil)
        await fulfillment(of: [refreshExpectation], timeout: 1.0)

        XCTAssertTrue(monitor.isAvailable)
        XCTAssertEqual(monitor.biometryType, LABiometryType.touchID)
    }

    func testStartMonitoringIsIdempotentForLifecycleObservation() async {
        let center = NotificationCenter()
        var refreshCount = 0
        let refreshExpectation = expectation(description: "observes one lifecycle refresh")
        let monitor = BiometricMonitor(
            notificationCenter: center,
            activeNotificationName: .biometricMonitorDidBecomeActiveForTests,
            statusProvider: {
                refreshCount += 1
                if refreshCount == 3 {
                    refreshExpectation.fulfill()
                }
                return (true, .faceID)
            }
        )

        monitor.startMonitoring()
        monitor.startMonitoring()

        center.post(name: .biometricMonitorDidBecomeActiveForTests, object: nil)
        await fulfillment(of: [refreshExpectation], timeout: 1.0)

        XCTAssertEqual(refreshCount, 3)
    }
}

private extension Notification.Name {
    static let biometricMonitorDidBecomeActiveForTests = Notification.Name("BiometricMonitorDidBecomeActiveForTests")
}
