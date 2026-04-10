import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class DevicePresenceReporterTests: XCTestCase {
    private struct PresenceUpdate: Equatable {
        let token: String
        let isForeground: Bool
        let lastSeenAt: String?
    }

    func testScenePhaseTransitionsEmitForegroundAndBackgroundUpdates() async {
        var captured: [PresenceUpdate] = []
        var now = Date(timeIntervalSince1970: 1_710_000_000)
        let reporter = DevicePresenceReporter(
            throttleInterval: 30,
            now: { now },
            sendPresenceUpdate: { token, isForeground, lastSeenAt in
                captured.append(
                    PresenceUpdate(
                        token: token,
                        isForeground: isForeground,
                        lastSeenAt: lastSeenAt
                    )
                )
            }
        )

        await reporter.report(scenePhase: .active, token: "abc123")
        now.addTimeInterval(1)
        await reporter.report(scenePhase: .background, token: "abc123")

        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[0].token, "abc123")
        XCTAssertTrue(captured[0].isForeground)
        XCTAssertEqual(captured[0].lastSeenAt, "2024-03-09T16:00:00Z")
        XCTAssertEqual(captured[1].token, "abc123")
        XCTAssertFalse(captured[1].isForeground)
        XCTAssertEqual(captured[1].lastSeenAt, "2024-03-09T16:00:01Z")
    }

    func testRepeatedEffectiveStateIsThrottled() async {
        var captured: [PresenceUpdate] = []
        var now = Date(timeIntervalSince1970: 1_710_000_100)
        let reporter = DevicePresenceReporter(
            throttleInterval: 30,
            now: { now },
            sendPresenceUpdate: { token, isForeground, lastSeenAt in
                captured.append(
                    PresenceUpdate(
                        token: token,
                        isForeground: isForeground,
                        lastSeenAt: lastSeenAt
                    )
                )
            }
        )

        await reporter.report(scenePhase: .inactive, token: "abc123")
        now.addTimeInterval(1)
        await reporter.report(scenePhase: .background, token: "abc123")
        now.addTimeInterval(1)
        await reporter.report(scenePhase: .inactive, token: "abc123")

        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].token, "abc123")
        XCTAssertFalse(captured[0].isForeground)
        XCTAssertEqual(captured[0].lastSeenAt, "2024-03-09T16:01:40Z")
    }
}
